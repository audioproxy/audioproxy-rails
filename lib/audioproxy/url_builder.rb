require "base64"
require "active_support/core_ext/object/blank"
require "audioproxy/expiry"

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

    # Typed option keys (+f:+, +br:+, +t:+ …) arrive as keyword arguments and
    # render in the order they were written. Each is also accepted as its
    # spelled-out alias (+format:+, +bitrate:+, +trim:+ …), resolved to the
    # canonical key before anything is rendered. A keyword that is neither a
    # builder option nor a proxy option key raises rather than being ignored.
    #
    # +expires_in:+ (a duration or Integer seconds from now) and +expires_at:+
    # (the instant itself) are mutually exclusive and time-box this one URL,
    # overriding +config.expires_in+; either given as nil opts out of it (D6).
    def url_for(source, raw: nil, endpoint: nil, unsigned: nil,
                expires_in: Expiry::UNSET, expires_at: Expiry::UNSET, **typed)
      base = endpoint.nil? ? config.endpoint : Config.new.tap { |c| c.endpoint = endpoint }.endpoint
      raise ConfigurationError, "Audioproxy has no endpoint configured" if base.nil?

      # Once per URL, so the window arithmetic and the past-check cannot
      # straddle a second boundary (D4).
      expiry = Expiry.timestamp(
        expires_in: expires_in, expires_at: expires_at,
        default_expires_in: config.expires_in, now: Time.now.to_i
      )

      rest_of_path = "/#{options_segment(raw, typed, expiry)}/#{source_segment(source)}"
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
      # Precedence, per D4: an explicit per-call source of options replaces the
      # configured defaults entirely; typed per-call keys merge over typed
      # defaults key-by-key, keeping the defaults' position and appending the
      # rest in caller order.
      def options_segment(raw, typed, expiry)
        with_expiry(variant_segment(raw, typed), expiry)
      end

      def variant_segment(raw, typed)
        unless raw.nil? || typed.empty?
          raise ArgumentError,
            "Audioproxy url_for takes either raw: or typed option keys, not both " \
            "(got raw: and #{typed.keys.join(", ")})"
        end

        return raw_segment(raw) unless raw.nil?

        # Onto the canonical keys before anything else, so that a default
        # written as bitrate: and a per-call br: are one key the merge
        # overrides rather than two segments that both render (D3). Defaults
        # were resolved at assignment.
        typed = Options.resolve(typed)
        reject_expiry_option!(typed)

        defaults = config.default_options
        typed_defaults = defaults.except(:raw)

        return Options.render(typed_defaults.merge(typed)) unless typed.empty?
        return raw_segment(defaults[:raw]) unless defaults[:raw].nil?
        return Options.render(typed_defaults) unless typed_defaults.empty?

        FALLBACK_OPTIONS
      end

      # exp is a *request* option: signed as path bytes, but excluded from the
      # proxy's cache key, so it is orthogonal to the variant options that
      # raw: and the typed keys describe and composes with either (D3). It goes
      # last, which leaves the variant prefix byte-identical to the same call
      # without an expiry.
      def with_expiry(segment, expiry)
        return segment if expiry.nil?

        # A raw: string that already spells out exp: would give the proxy two of
        # them and a duplicate-option 422 — a failure the caller never wrote if
        # the second one came from config.expires_in.
        if segment.split("/").any? { |part| part.start_with?("exp:") }
          raise ArgumentError,
            "Audioproxy url_for was given raw options that already carry an exp: segment " \
            "(#{segment.inspect}) and an expiry to apply; the proxy rejects a duplicated option. " \
            "Drop the exp: from raw:, or pass expires_in: nil to opt this URL out"
        end

        "#{segment}/#{Options.segment(:exp, expiry)}"
      end

      # exp: written as an ordinary option skips every check in Expiry, and the
      # two mistakes it invites — a timestamp already past, a millisecond
      # timestamp — both render a URL that looks right and never works (D1).
      def reject_expiry_option!(typed)
        return unless typed.key?(:exp)

        raise ArgumentError,
          "Audioproxy url_for does not take exp: as an option key; " \
          "pass expires_in: (a duration from now) or expires_at: (the instant), " \
          "which validate the value and do the arithmetic"
      end

      def raw_segment(raw)
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
        string = String.try_convert(source) || resolved_source(source)
        if string.empty?
          raise ArgumentError, "source must not be empty"
        end

        "enc/#{base64url(string)}"
      end

      # Non-String sources go through the registered resolver, or nowhere. The
      # core names no ActiveStorage constant; it only knows that something else
      # may have claimed the job of turning objects into source strings.
      def resolved_source(source)
        resolver = Audioproxy.source_resolver
        if resolver.nil?
          raise ArgumentError,
            "source must be a String, got #{source.class} (ActiveStorage blobs " \
            "and attachments resolve only where the Rails integration is loaded)"
        end

        resolved = resolver.call(source)
        string = String.try_convert(resolved)
        if string.nil?
          raise ArgumentError,
            "the registered Audioproxy source resolver returned #{resolved.class} " \
            "for #{source.class}, not a source String"
        end

        string
      end

      # Unpadded, per D3/D4: the proxy accepts both spellings, but emitting one
      # keeps URLs and CDN cache keys stable.
      def base64url(bytes)
        Base64.urlsafe_encode64(bytes, padding: false)
      end
  end
end
