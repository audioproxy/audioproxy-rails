require "openssl"

module Audioproxy
  # Assembles +{endpoint}/{signature}/{options}/{source}+ URLs, byte-compatible
  # with the proxy's reference signer.
  #
  # The signature covers everything after itself (leading +/+ included), so an
  # endpoint path prefix cannot disturb it.
  class UrlBuilder
    # Literal signature segment the proxy accepts under AP_ALLOW_INSECURE.
    INSECURE_SEGMENT = "insecure".freeze

    # The proxy's path grammar has no optionless form, so the minimal
    # always-valid options string is its default format spelled out.
    FALLBACK_OPTIONS = "f:mp3".freeze

    attr_reader :config

    def initialize(config = Audioproxy.config)
      @config = config
    end

    def url_for(source, raw: nil, endpoint: nil, unsigned: nil)
      base = endpoint.nil? ? config.endpoint : Config.new.tap { |c| c.endpoint = endpoint }.endpoint
      raise ConfigurationError, "Audioproxy has no endpoint configured" if base.nil?

      rest_of_path = "/#{options_segment(raw)}/#{source_segment(source)}"
      insecure = unsigned.nil? ? config.unsigned : unsigned

      "#{base}/#{insecure ? INSECURE_SEGMENT : sign(rest_of_path)}#{rest_of_path}"
    end

    # base64url(HMAC-SHA256(key, salt ‖ rest_of_path)), unpadded.
    def sign(rest_of_path)
      unless rest_of_path.start_with?("/")
        raise ArgumentError, "rest_of_path must begin with '/' to be verifiable at the proxy, got #{rest_of_path.inspect}"
      end

      missing = [ (:key unless config.key), (:salt unless config.salt) ].compact
      unless missing.empty?
        raise ConfigurationError, "Audioproxy cannot sign a URL: #{missing.join(" and ")} not configured (set them, or use unsigned: true)"
      end

      base64url OpenSSL::HMAC.digest("SHA256", config.key, config.salt + rest_of_path.b)
    end

    private
      def options_segment(raw)
        raw = config.default_options[:raw] if raw.nil?
        return FALLBACK_OPTIONS if raw.nil?

        segment = String.try_convert(raw)
        if segment.nil?
          raise ArgumentError, "raw options must be a String, got #{raw.class}"
        end

        segment = segment.strip
        return FALLBACK_OPTIONS if segment.empty?

        # The builder supplies the separators. A bracketing slash would sign a
        # path with an empty segment, which the proxy rejects — and it would do
        # so at request time, nowhere near this call.
        if segment.start_with?("/") || segment.end_with?("/")
          raise ArgumentError, "raw options must not begin or end with '/', got #{segment.inspect}"
        end

        segment
      end

      # The proxy accepts padded and unpadded enc/ payloads; emitting exactly
      # one spelling keeps URLs (and CDN cache keys) stable.
      def source_segment(source)
        string = String.try_convert(source)
        if string.nil?
          raise ArgumentError, "source must be a String, got #{source.class}"
        end
        if string.empty?
          raise ArgumentError, "source must not be empty"
        end

        "enc/#{base64url(string)}"
      end

      def base64url(bytes)
        [ bytes ].pack("m0").tr("+/", "-_").delete("=")
      end
  end
end
