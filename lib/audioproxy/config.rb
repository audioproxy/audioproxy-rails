require "uri"
require "active_support/core_ext/hash/keys"

module Audioproxy
  # Raised when a URL is requested but the configuration cannot produce one the
  # proxy would accept (missing endpoint, or missing signing material outside of
  # unsigned mode).
  class ConfigurationError < StandardError; end

  # Process-global settings for URL generation. Assign through
  # +Audioproxy.configure+; every attribute validates at assignment so a typo
  # fails at boot rather than in a mailer.
  class Config
    HEX = /\A(?:\h\h)+\z/

    # Option keys defaults may carry: the proxy's typed short keys, plus the
    # pre-rendered +raw:+ escape hatch. An unrecognized key is a typo, and a
    # typo that is silently dropped emits a valid URL for the wrong variant.
    OPTION_KEYS = ([ :raw ] + Options::KEYS).freeze

    attr_reader :endpoint, :key, :salt, :default_options
    attr_accessor :unsigned

    def initialize
      @endpoint = nil
      @key = nil
      @salt = nil
      @unsigned = false
      @default_options = {}
    end

    # Full base URL of the proxy: scheme + host, optionally with a path prefix
    # (a CDN routing +/audio+ to the proxy, say). One trailing slash is dropped
    # so joining is a plain concatenation.
    def endpoint=(value)
      @endpoint = value.nil? ? nil : normalize_endpoint(value)
    end

    # Options applied to every URL unless overridden per call. Keys may be given
    # as strings or symbols; they are normalized to symbols.
    def default_options=(value)
      @default_options = normalize_default_options(value)
    end

    # Hex signing key, decoded to binary at assignment.
    def key=(value)
      @key = decode_hex(value, :key)
    end

    # Hex salt, decoded to binary at assignment.
    def salt=(value)
      @salt = decode_hex(value, :salt)
    end

    private
      def decode_hex(value, attribute)
        return nil if value.nil?

        hex = String.try_convert(value)
        if hex.nil?
          raise ArgumentError, "Audioproxy config #{attribute} must be a hex String, got #{value.class}"
        end

        unless hex.match?(HEX)
          raise ArgumentError, "Audioproxy config #{attribute} must be a non-empty, even-length hex string, got #{value.inspect}"
        end

        [ hex ].pack("H*")
      end

      def normalize_endpoint(value)
        endpoint = String.try_convert(value)
        if endpoint.nil?
          raise ArgumentError, "Audioproxy config endpoint must be a String, got #{value.class}"
        end

        uri = begin
          URI.parse(endpoint)
        rescue URI::InvalidURIError
          nil
        end

        unless uri.is_a?(URI::HTTP) && uri.host && !uri.host.empty?
          raise ArgumentError, "Audioproxy config endpoint must be an absolute http(s) URL, got #{value.inspect}"
        end

        # A base URL is scheme + host + optional path prefix and nothing else.
        # Userinfo would put credentials into every generated URL (and so into
        # HTML, logs and CDN access logs); a query or fragment would swallow the
        # path we append after it.
        if uri.userinfo
          raise ArgumentError, "Audioproxy config endpoint must not carry userinfo (credentials would leak into every URL)"
        end
        if uri.query || uri.fragment
          raise ArgumentError, "Audioproxy config endpoint must not carry a query or fragment, got #{value.inspect}"
        end

        # delete_suffix removes exactly one occurrence, which is what D5 says.
        endpoint.delete_suffix("/")
      end

      def normalize_default_options(value)
        return {} if value.nil?

        unless value.is_a?(Hash)
          raise ArgumentError, "Audioproxy config default_options must be a Hash, got #{value.class}"
        end

        value.each_key do |key|
          unless key.is_a?(String) || key.is_a?(Symbol)
            raise ArgumentError, "Audioproxy config default_options keys must be Strings or Symbols, got #{key.class}"
          end
        end

        normalized = value.symbolize_keys
        # Raises ArgumentError: "Unknown key: :format. Valid keys are: :raw, :bd, …"
        normalized.assert_valid_keys(*OPTION_KEYS)

        # Two sources of truth for one segment string is ambiguity, not
        # composition — the same rule as per call (D4), applied at boot.
        if normalized.key?(:raw) && normalized.keys.size > 1
          raise ArgumentError,
            "Audioproxy config default_options takes either raw: or typed option keys, not both " \
            "(got raw: and #{(normalized.keys - [ :raw ]).join(", ")})"
        end

        normalized
      end
  end
end
