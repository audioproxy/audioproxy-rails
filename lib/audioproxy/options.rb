module Audioproxy
  # Renders the proxy's option grammar: +/+-separated +key:value+ segments,
  # with colon-separated parts for the multi-part keys.
  #
  # This layer renders, it does not validate (D1). Value domains and cross-key
  # rules belong to the proxy, which versions them with the server and returns
  # structured 422s. The exceptions are values this module cannot render
  # faithfully — an unknown key, a number that does not fit the grammar, a value
  # carrying a separator — because a mangled segment is a valid-looking URL for
  # the wrong variant, and it fails at request time, far from here.
  module Options
    # The proxy's fourteen option keys, canonical short spellings.
    KEYS = %i[bd br cb ch dl f fade gain norm pk_fmt pts q sr t].freeze

    # Keys whose grammar takes colon-separated parts: +t:START[:DURATION]+,
    # +fade:IN[:OUT]+, +norm:ebu[:I[:TP[:LRA]]]+.
    MULTI_PART_KEYS = %i[t fade norm].freeze

    # Keys the proxy treats as opaque payloads (download filename, cache
    # buster), rendered verbatim rather than number-formatted.
    OPAQUE_KEYS = %i[cb dl].freeze

    # The proxy caps decimals at 3 places when it parses, and hashes the
    # normalized options string into its cache key.
    MAX_DECIMALS = 3

    class << self
      # Renders an ordered key => value Hash into an options segment. Caller
      # order is preserved (D4); normalization is the proxy's business.
      def render(options)
        options.map { |key, value| segment(key, value) }.join("/")
      end

      # Renders one +key:value+ segment.
      def segment(key, value)
        key = symbolize(key)
        unless KEYS.include?(key)
          raise ArgumentError, "unknown Audioproxy option #{key.inspect}; known keys are #{KEYS.join(", ")}"
        end

        rendered = render_value(key, value)
        if rendered.empty?
          raise ArgumentError, "Audioproxy option #{key}: rendered to an empty value"
        end
        # A slash would silently split one segment into two and shift the whole
        # path — signed, accepted by nothing.
        if rendered.include?("/")
          raise ArgumentError, "Audioproxy option #{key}: must not contain '/', got #{rendered.inspect} (use raw: to write a whole options string)"
        end

        "#{key}:#{rendered}"
      end

      # The proxy's canonical minimal number spelling. Strings and symbols pass
      # through untouched — the caller opted out of formatting.
      #
      # Rendering goes through an explicit decimal path rather than Float#to_s,
      # which produces the +1.0e-05+ exponent forms the grammar rejects.
      def format_number(value)
        case value
        when String then value
        when Symbol then value.to_s
        when Integer then value.to_s
        when Numeric then format_decimal(value)
        else
          raise ArgumentError, "Audioproxy option values must be numbers, strings or symbols, got #{value.class}"
        end
      end

      private
        def symbolize(key)
          case key
          when Symbol then key
          when String then key.to_sym
          else
            raise ArgumentError, "Audioproxy option keys must be Symbols or Strings, got #{key.class}"
          end
        end

        def render_value(key, value)
          return render_parts(key, value) if value.is_a?(Array)

          format_part(key, value)
        end

        def render_parts(key, value)
          unless MULTI_PART_KEYS.include?(key)
            raise ArgumentError,
              "Audioproxy option #{key}: takes a single value, got #{value.inspect}; " \
              "only #{MULTI_PART_KEYS.join(", ")} take colon-separated parts"
          end
          if value.empty?
            raise ArgumentError, "Audioproxy option #{key}: was given an empty Array"
          end

          value.map { |part| format_part(key, part) }.join(":")
        end

        # dl: and cb: are opaque to the proxy, so they are opaque here too: a
        # filename or cache buster is whatever the caller wrote.
        def format_part(key, value)
          return format_number(value) unless OPAQUE_KEYS.include?(key)

          case value
          when String then value
          when Symbol, Numeric then format_number(value)
          else
            raise ArgumentError, "Audioproxy option #{key}: must be a String, Symbol or number, got #{value.class}"
          end
        end

        def format_decimal(value)
          unless value.finite?
            raise ArgumentError, "Audioproxy option value #{value} is not a finite number"
          end

          rounded = value.round(MAX_DECIMALS)
          unless rounded == value
            raise ArgumentError,
              "Audioproxy option value #{value.inspect} needs more than #{MAX_DECIMALS} decimal places; " \
              "the proxy caps decimals at #{MAX_DECIMALS} and rejects the rest as excessive precision. " \
              "Round explicitly at the call site if that is what you mean."
          end

          # -0.0 collapses here too: it equals its own truncation.
          return rounded.to_i.to_s if rounded == rounded.to_i

          # Always MAX_DECIMALS places, so trimming trailing zeros can never eat
          # a digit before the point.
          format("%.#{MAX_DECIMALS}f", rounded).sub(/0+\z/, "")
        end
    end
  end
end
