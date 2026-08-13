require "uri"
require "active_support/core_ext/hash/keys"
require "audioproxy/options"
require "audioproxy/expiry"

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

    # Option keys defaults may carry: the proxy's typed short keys and their
    # spelled-out aliases, plus the pre-rendered +raw:+ escape hatch. An
    # unrecognized key is a typo, and a typo that is silently dropped emits a
    # valid URL for the wrong variant.
    #
    # exp is subtracted deliberately (D1). It is an absolute instant, so a
    # default would expire every URL the process ever mints at one second, and
    # it would skip the validation the keywords run. +expires_in+ below is the
    # default that makes sense.
    EXPIRY_KEYS = ([ :exp ] + Options::REQUEST_KEYS.map { |key| Options::ALIASES[key] }).uniq.freeze
    OPTION_KEYS = (([ :raw ] + Options::KEYS + Options::ALIASES.values).uniq - EXPIRY_KEYS).freeze

    attr_reader :endpoint, :key, :salt, :default_options, :expires_in
    attr_accessor :unsigned

    def initialize
      @endpoint = nil
      @key = nil
      @salt = nil
      @unsigned = false
      @default_options = {}
      @expires_in = nil
    end

    # How long a URL stays valid, applied to every URL this process builds.
    # nil — the default — means URLs carry no expiry and remain the eternal
    # bearer capabilities they have always been.
    #
    # A duration rather than an instant, and validated here so a typo fails at
    # boot rather than in a mailer. A call site overrides it with its own
    # +expires_in:+/+expires_at:+, or opts one URL out with +expires_in: nil+.
    def expires_in=(value)
      @expires_in = value.nil? ? nil : Expiry.seconds(value, source: "config expires_in")
    end

    # Full base URL of the proxy: scheme + host, optionally with a path prefix
    # (a CDN routing +/audio+ to the proxy, say). One trailing slash is dropped
    # so joining is a plain concatenation.
    def endpoint=(value)
      @endpoint = value.nil? ? nil : normalize_endpoint(value)
    end

    # Options applied to every URL unless overridden per call. Keys may be given
    # as strings or symbols, canonical or spelled-out; they are normalized to
    # canonical symbols here, which is what makes an aliased default and a
    # canonical per-call key one key in the merge rather than two segments (D3).
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

        # Before symbolize_keys, which collapses "br" and :br into one entry and
        # silently discards a value — the typo that OPTION_KEYS exists to catch.
        duplicate = value.keys.group_by(&:to_sym).find { |_, spellings| spellings.size > 1 }
        if duplicate
          key, spellings = duplicate
          raise ArgumentError,
            "Audioproxy config default_options gives #{key} twice, as " \
            "#{spellings.map(&:inspect).join(" and ")}; each option takes one spelling"
        end

        normalized = value.symbolize_keys

        # Before the generic unknown-key message, which would report exp as a
        # typo when it is a real option reached a different way (D1).
        unless (expiry = normalized.keys & EXPIRY_KEYS).empty?
          raise ArgumentError,
            "Audioproxy config default_options must not carry #{expiry.first.inspect}: it is an " \
            "absolute instant, so every URL this process builds would expire at the same second. " \
            "Set config.expires_in to a duration instead, or pass expires_in:/expires_at: per call"
        end

        # Not assert_valid_keys: its message lists the aliases among the valid
        # keys without saying they are aliases, so a caller who guessed
        # bit_rate: sees :bitrate in a flat list and cannot tell the two
        # vocabularies apart.
        unless (unknown = normalized.keys - OPTION_KEYS).empty?
          raise ArgumentError,
            "unknown Audioproxy option #{unknown.first.inspect} in default_options; known keys are " \
            "#{([ :raw ] + Options::KEYS - EXPIRY_KEYS).join(", ")}, each also accepted as its spelled-out alias " \
            "(#{Options::ALIASES[:br]}, #{Options::ALIASES[:sr]}, #{Options::ALIASES[:pk_fmt]}, …)"
        end

        # Two sources of truth for one segment string is ambiguity, not
        # composition — the same rule as per call (D4), applied at boot.
        if normalized.key?(:raw) && normalized.keys.size > 1
          raise ArgumentError,
            "Audioproxy config default_options takes either raw: or typed option keys, not both " \
            "(got raw: and #{(normalized.keys - [ :raw ]).join(", ")})"
        end

        # Both spellings of one option is the same ambiguity, and assignment
        # time is where it should fail: at boot, not in a mailer.
        Options.resolve(normalized)
      end
  end
end
