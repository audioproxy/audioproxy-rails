require_relative "../fixtures/signature_vectors"
require_relative "proxy_container"

module Audioproxy
  module Test
    # The `:server` tag (D3). Minitest has no tag facility, so the tag is this
    # module: including it makes a case opt-in.
    #
    # Two separate gates, and the difference matters:
    #
    #   AUDIOPROXY_SERVER_TESTS unset    the group is not being asked for, so
    #                                    `bin/test` stays a fast, Docker-free
    #                                    unit run on a laptop with no network
    #   set, but Docker unreachable      it was asked for and cannot run; the
    #                                    contributor's environment is broken,
    #                                    not the gem
    #
    # Both skip rather than fail. CI closes the hole that opens *outside* the
    # suite, by pulling the image in its own step before running this group, so
    # a ghcr outage fails by name rather than laundering itself into a silent
    # pass.
    module ServerRoundtrip
      extend ActiveSupport::Concern

      ENV_FLAG = "AUDIOPROXY_SERVER_TESTS".freeze

      included do
        setup do
          unless ENV[ENV_FLAG]
            skip "#{ENV_FLAG} is unset; run bin/test-server to exercise #{ProxyContainer.describe}"
          end

          unless ProxyContainer.available?
            skip "no reachable Docker daemon, so #{ProxyContainer.describe} cannot be booted"
          end

          @config = Audioproxy::Config.new
          @config.endpoint = ProxyContainer.endpoint
          @config.key      = ProxyContainer::KEY
          @config.salt     = ProxyContainer::SALT
        end
      end

      def url_for(source = ProxyContainer::SOURCE, **options)
        Audioproxy::UrlBuilder.new(@config).url_for(source, **options)
      end

      def get(url)
        uri = URI(url)
        Net::HTTP.start(uri.host, uri.port, open_timeout: 5, read_timeout: 30) do |http|
          http.get(uri.request_uri)
        end
      end

      # Every assertion in the group routes its message through here, so a
      # failure names the proxy version it ran against (task 1.4). A mismatch
      # between this gem and an upstream release is otherwise indistinguishable
      # from a bug in this gem.
      def against_proxy(message, response = nil)
        detail = response && "; body: #{response.body.to_s[0, 200].inspect}"
        "#{message} — against #{ProxyContainer.describe}#{detail}"
      end
    end
  end
end
