require "net/http"
require "open3"
require "socket"
require "fileutils"

module Audioproxy
  module Test
    # Boots one real audioproxy container for the `:server` group and tears it
    # down when the suite ends.
    #
    # The tag is pinned rather than tracking `latest` (D2): a suite that follows
    # the proxy's newest release turns an upstream change into a failure here
    # with no commit here to blame. Every failure message this module produces
    # names +IMAGE+ for that reason — a version mismatch has to be legible from
    # the failure alone.
    #
    # **Advancing the pin is part of the proxy's release checklist** (D8). See
    # the round-trip section of the README.
    module ProxyContainer
      TAG   = "0.6.0".freeze
      IMAGE = "ghcr.io/audioproxy/audioproxy:#{TAG}".freeze

      # The published manifest is amd64-only, so a plain pull fails on Apple
      # Silicon with "no matching manifest for linux/arm64/v8". Requesting the
      # platform explicitly is a no-op on amd64 hosts and selects emulation on
      # arm64 ones. If the proxy ever publishes arm64 this becomes redundant
      # rather than wrong.
      PLATFORM = "linux/amd64".freeze

      # Per-process, so two runs on one machine (two terminals, or a `bin/test`
      # and a `bin/test-server` side by side) cannot evict each other's
      # container. An earlier version used a fixed name and force-removed it at
      # boot, which cleaned up after a crashed run by breaking a concurrent one.
      NAME = "audioproxy-rails-roundtrip-#{Process.pid}".freeze

      # What a crashed run leaves behind is findable without knowing its pid:
      #   docker rm --force $(docker ps -aq --filter label=#{LABEL})
      LABEL = "audioproxy-rails-roundtrip".freeze

      # The signature vectors' key and salt, so the bytes the round-trip
      # exercises are the bytes the known-answer vectors pin (D4).
      KEY  = SignatureVectors::KEY_HEX
      SALT = SignatureVectors::SALT_HEX

      # Sources are `local://` over this bind-mounted root (D1). The root is
      # deliberately absent from the source string: the proxy keeps
      # AP_LOCAL_ROOT out of a source's identity.
      CONTAINER_ROOT = "/srv/audio".freeze
      FIXTURE_NAME   = "tone.wav".freeze
      SOURCE         = "local://#{FIXTURE_NAME}".freeze

      # An emulated BEAM boot measured at about three seconds; sixty is room for
      # a cold CI runner without being an unbounded hang.
      BOOT_TIMEOUT = 60

      class << self
        # True when this machine can run the group at all. Deliberately quiet:
        # a contributor whose Docker daemon is stopped has a broken environment,
        # not a broken gem, so the group skips (D3).
        def available?
          return @available if defined?(@available)

          @available = system("docker", "info", out: File::NULL, err: File::NULL)
        end

        # Boots the container once for the whole group and returns its base URL.
        def endpoint
          @endpoint ||= boot!
        end

        # Gated on the container having been *started*, not on the boot having
        # succeeded: a container that came up and never answered /health is
        # precisely the one that needs removing.
        def stop!
          return unless @started

          system("docker", "rm", "--force", NAME, out: File::NULL, err: File::NULL)
          @started = false
          @endpoint = nil
        end

        # Named in every assertion so a failure says which proxy produced it.
        def describe
          "#{IMAGE} (pinned; advance it with the proxy's release — see README)"
        end

        private
          def boot!
            root = prepare_fixture_root
            port = free_port

            out, status = Open3.capture2e(
              "docker", "run", "--detach",
              "--name", NAME,
              "--label", LABEL,
              "--platform", PLATFORM,
              "--publish", "127.0.0.1:#{port}:4000",
              "--env", "AP_KEY=#{KEY}",
              "--env", "AP_SALT=#{SALT}",
              # Signed and unsigned in one container: verify/2 special-cases only
              # the literal `insecure` segment, so every other signature still
              # goes through the HMAC comparison (D4).
              "--env", "AP_ALLOW_INSECURE=true",
              "--env", "AP_LOCAL_ROOT=#{CONTAINER_ROOT}",
              "--volume", "#{root}:#{CONTAINER_ROOT}:ro",
              IMAGE
            )

            unless status.success?
              raise "could not start #{describe}: #{out.strip}"
            end

            # Registered *before* the health wait, not after. await_health
            # raises on a container that started and never became ready, which
            # is exactly the case where cleanup matters — and the obvious
            # ordering skips it, leaking the container that just failed to boot.
            @started = true
            at_exit { stop! }

            url = "http://127.0.0.1:#{port}"
            await_health(url)
            url
          end

          def await_health(url)
            deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + BOOT_TIMEOUT

            loop do
              return if healthy?(url)

              if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
                logs, = Open3.capture2e("docker", "logs", NAME)
                raise "#{describe} did not answer /health within #{BOOT_TIMEOUT}s: #{logs.strip}"
              end

              sleep 0.25
            end
          end

          def healthy?(url)
            uri = URI.join(url, "/health")
            Net::HTTP.start(uri.host, uri.port, open_timeout: 1, read_timeout: 1) do |http|
              http.get(uri.request_uri).code == "200"
            end
          rescue SystemCallError, IOError, Timeout::Error
            false
          end

          # A one-second 8 kHz mono PCM sine, generated rather than committed
          # (D1): sixteen kilobytes of pack(), no ffmpeg needed on this side, and
          # no binary in the repository. tmp/ is already gitignored.
          def prepare_fixture_root
            root = File.expand_path("../../tmp/roundtrip-root", __dir__)
            FileUtils.mkdir_p(root)

            # Written every time rather than reused. tmp/ survives across runs
            # and branches, so a file left truncated by a run interrupted
            # mid-write would otherwise be reused forever — and the symptom is
            # an ffmpeg decode failure inside the container, which points
            # nowhere near the cause. Sixteen kilobytes costs nothing.
            path = File.join(root, FIXTURE_NAME)
            File.binwrite(path, wav)

            # The container runs as uid 1000, which is not necessarily this user.
            FileUtils.chmod(0o755, root)
            FileUtils.chmod(0o644, path)

            root
          end

          def wav(rate: 8_000, seconds: 1, hz: 440)
            samples = (rate * seconds).times.map { |i| (Math.sin(2 * Math::PI * hz * i / rate) * 8_000).round }
            data = samples.pack("s<*")

            header = [
              "RIFF", 36 + data.bytesize, "WAVE",
              "fmt ", 16, 1, 1, rate, rate * 2, 2, 16,
              "data", data.bytesize
            ].pack("a4Va4a4VvvVVvva4V")

            header + data
          end

          # Bound and released so the container can take it. A race here would
          # surface as a failed `docker run`, which is loud rather than subtle.
          def free_port
            server = TCPServer.new("127.0.0.1", 0)
            port = server.addr[1]
            server.close
            port
          end
      end
    end
  end
end
