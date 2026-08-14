require "net/http"
require "json"
require "fileutils"
require_relative "../fixtures/signature_vectors"

module Audioproxy
  module Test
    # The `:server` tag. Minitest has no tag facility, so the tag is this
    # module: including it makes a case opt-in.
    #
    # This gem does not start the proxy. CI runs one as a service container and
    # the README gives the `docker run` line for a laptop; either way the group
    # is told where it is through `AUDIOPROXY_PROXY_URL` and does nothing but
    # talk to it. An earlier version orchestrated the container from Ruby —
    # port allocation, health polling, cleanup hooks, per-process naming — and
    # every defect the outside review found was in that machinery rather than
    # in anything being tested.
    #
    # The variable is the whole gate, and it means "there is a proxy at this
    # address". So an unreachable proxy is a **failure**, not a skip: a run that
    # was asked to exercise a proxy and silently exercised nothing is the one
    # outcome this group must never produce.
    module ServerRoundtrip
      extend ActiveSupport::Concern

      # The proxy release this suite is written against. It appears here and in
      # `.github/workflows/ci.yml`, which is a duplication with teeth: `setup`
      # asks the running proxy its version and refuses to run against a
      # different one, so the two drifting is a named failure rather than a
      # suite that quietly tests the wrong thing.
      PROXY_VERSION = "0.6.0".freeze
      IMAGE = "ghcr.io/audioproxy/audioproxy:#{PROXY_VERSION}".freeze

      URL_VAR  = "AUDIOPROXY_PROXY_URL".freeze
      ROOT_VAR = "AUDIOPROXY_FIXTURE_ROOT".freeze

      # Shared by the README's `docker run -v` and CI's `services.volumes`, so
      # one path is correct in both. The proxy keeps `AP_LOCAL_ROOT` out of a
      # source's identity, so the mount point inside the container is its own
      # business and never appears in a signed URL.
      DEFAULT_FIXTURE_ROOT = "/tmp/audioproxy-fixtures".freeze

      FIXTURE_NAME = "tone.wav".freeze
      SOURCE       = "local://#{FIXTURE_NAME}".freeze

      # The signature vectors' own key and salt, so the bytes these round-trips
      # exercise are the bytes the known-answer vectors pin.
      KEY  = SignatureVectors::KEY_HEX
      SALT = SignatureVectors::SALT_HEX

      class << self
        def proxy_url
          ENV[URL_VAR]
        end

        def fixture_root
          ENV[ROOT_VAR] || DEFAULT_FIXTURE_ROOT
        end

        def describe
          "#{IMAGE} at #{proxy_url}"
        end

        # Asked once, and the answer is the whole version-pinning story: this
        # reports what actually answered rather than what a constant claims was
        # started.
        def verify_version!
          @verified ||= begin
            running = health.fetch("version", nil)

            unless running == PROXY_VERSION
              raise "#{proxy_url} is audioproxy #{running.inspect}, but this suite is written " \
                    "against #{PROXY_VERSION} (#{IMAGE}). Point #{URL_VAR} at the pinned tag, or — " \
                    "if the suite has been updated for a newer proxy — advance PROXY_VERSION in " \
                    "test/support/server_roundtrip.rb and the image in .github/workflows/ci.yml."
            end

            true
          end
        end

        # The container reads this as uid 1000, which is not necessarily whoever
        # runs the tests. Written every time rather than reused: the directory
        # outlives the run, so a file left truncated by an interrupted one would
        # otherwise be reused forever, and the symptom is an ffmpeg decode
        # failure inside the container that points nowhere near the cause.
        def write_fixture!
          FileUtils.mkdir_p(fixture_root)
          path = File.join(fixture_root, FIXTURE_NAME)
          File.binwrite(path, wav)
          FileUtils.chmod(0o644, path)
          path
        end

        private
          def health
            uri = URI.join(proxy_url, "/health")
            JSON.parse(Net::HTTP.get_response(uri).body)
          rescue StandardError => e
            raise "no audioproxy answering /health at #{proxy_url} (#{e.class}: #{e.message}). " \
                  "#{URL_VAR} is set, so this is a failure rather than a skip — start #{IMAGE} as " \
                  "the README's round-trip section describes, or unset #{URL_VAR}."
          end

          # A one-second 8 kHz mono PCM sine. Generated rather than committed:
          # sixteen kilobytes of pack(), no ffmpeg needed on this side, and no
          # binary in the repository.
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
      end

      included do
        setup do
          if ServerRoundtrip.proxy_url.blank?
            skip "#{URL_VAR} is unset; see \"Round-trip tests against a real proxy\" in the README"
          end

          ServerRoundtrip.verify_version!
          ServerRoundtrip.write_fixture!

          @config = Audioproxy::Config.new
          @config.endpoint = ServerRoundtrip.proxy_url
          @config.key      = ServerRoundtrip::KEY
          @config.salt     = ServerRoundtrip::SALT
        end
      end

      def url_for(source = SOURCE, **options)
        Audioproxy::UrlBuilder.new(@config).url_for(source, **options)
      end

      def get(url)
        uri = URI(url)
        Net::HTTP.start(uri.host, uri.port, open_timeout: 5, read_timeout: 30) do |http|
          http.get(uri.request_uri)
        end
      end

      # Every assertion routes its message through here, so a failure names the
      # proxy it ran against. A disagreement between this gem and an upstream
      # release is otherwise indistinguishable from a bug in this gem.
      def against_proxy(message, response = nil)
        detail = response && "; body: #{response.body.to_s[0, 200].inspect}"
        "#{message} — against #{ServerRoundtrip.describe}#{detail}"
      end
    end
  end
end
