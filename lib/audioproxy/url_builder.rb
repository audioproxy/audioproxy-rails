require "base64"
require "active_support/core_ext/object/blank"

module Audioproxy
  # Assembles +{endpoint}/{signature}/{options}/{source}+ URLs, byte-compatible
  # with the proxy's reference signer.
  #
  # The signature covers everything after itself (leading +/+ included), so an
  # endpoint path prefix cannot disturb it.
  #
  # This is the Rails-facing half and may use ActiveSupport freely. The HMAC
  # itself lives in Audioproxy::Signer, which may not — see D1.
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

    # Signs via Audioproxy::Signer. Whether the config *can* sign is this
    # class's problem; how the bytes are produced is the signer's.
    def sign(rest_of_path)
      missing = [ (:key unless config.key), (:salt unless config.salt) ].compact
      unless missing.empty?
        raise ConfigurationError, "Audioproxy cannot sign a URL: #{missing.join(" and ")} not configured (set them, or use unsigned: true)"
      end

      Signer.new(key: config.key, salt: config.salt).sign(rest_of_path)
    end

    private
      def options_segment(raw)
        raw = config.default_options[:raw] if raw.nil?
        return FALLBACK_OPTIONS if raw.nil?

        segment = String.try_convert(raw)
        if segment.nil?
          raise ArgumentError, "raw options must be a String, got #{raw.class}"
        end

        return FALLBACK_OPTIONS if segment.blank?
        segment = segment.strip

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

      # Unpadded, per D3/D4: the proxy accepts both spellings, but emitting one
      # keeps URLs and CDN cache keys stable.
      def base64url(bytes)
        Base64.urlsafe_encode64(bytes, padding: false)
      end
  end
end
