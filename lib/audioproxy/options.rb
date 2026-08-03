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

    # Characters a rendered value may not carry. The builder supplies '/' and
    # ':', so a value containing either silently invents a segment or a part.
    # '?' and '#' end the path as far as a browser is concerned, which truncates
    # what the proxy receives below what was signed: a 403 at request time, far
    # from the call. Whitespace and control characters are not URL bytes at all.
    SEPARATORS = %r{[/:?#\s]|[[:cntrl:]]}

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

        "#{key}:#{render_value(key, value)}"
      end

      # The proxy's canonical minimal number spelling. Strings and symbols pass
      # through untouched — the caller opted out of formatting.
      def format_number(value)
        case value
        when String then value
        when Symbol then value.to_s
        when Integer then value.to_s
        when Complex
          # Numeric, but Complex#round is undefined and Complex#to_r silently
          # drops a zero imaginary part. Neither is a number this grammar has.
          raise ArgumentError, "Audioproxy option values must be real numbers, got #{value.inspect}"
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

        def format_part(key, value)
          rendered = render_part(key, value)

          # Every part is validated on its own, not the assembled segment: an
          # empty part between two separators (t::30) reads as a whole value.
          if rendered.empty?
            raise ArgumentError, "Audioproxy option #{key}: has an empty value"
          end
          if (offender = rendered[SEPARATORS])
            raise ArgumentError,
              "Audioproxy option #{key}: must not contain #{offender.inspect}, got #{rendered.inspect}. " \
              "The builder supplies the separators; pre-encode the value, or use raw: to write the whole options string."
          end

          rendered
        end

        # dl: and cb: are opaque to the proxy, so they are opaque here too: a
        # filename or cache buster is whatever the caller wrote.
        def render_part(key, value)
          return format_number(value) unless OPAQUE_KEYS.include?(key)

          case value
          when String then value
          when Symbol, Numeric then format_number(value)
          else
            raise ArgumentError, "Audioproxy option #{key}: must be a String, Symbol or number, got #{value.class}"
          end
        end

        # Rendering is exact integer arithmetic on the value's decimal form.
        # Neither Float#to_s nor format("%.3f") can do this job alone: the
        # former emits the +1.0e-05+ exponent shapes the grammar rejects, and
        # the latter re-reads the underlying binary value, so it renders
        # 12345678901234.56 as "12345678901234.561" and truncates a BigDecimal
        # to a double on the way past.
        def format_decimal(value)
          scaled = exact_decimal(value) * (10 ** MAX_DECIMALS)
          unless scaled.denominator == 1
            raise ArgumentError,
              "Audioproxy option value #{value.inspect} needs more than #{MAX_DECIMALS} decimal places; " \
              "the proxy caps decimals at #{MAX_DECIMALS} and rejects the rest as excessive precision. " \
              "Round explicitly at the call site if that is what you mean."
          end

          render_scaled(scaled.numerator)
        end

        # The exact decimal the caller meant, as a Rational.
        def exact_decimal(value)
          assert_finite!(value)

          case value
          when Float
            # Float#to_s is the shortest decimal that round-trips to this
            # double, which is the spelling the caller wrote. The double's own
            # expansion is another number entirely — 0.001 is really
            # 0.001000000000000000020816…, and rendering *that* would reject
            # every fractional float as excessive precision.
            Rational(value.to_s)
          when Rational then value
          else
            # BigDecimal and any other real Numeric: to_r is exact, which is
            # what a value carrying more digits than a double can hold needs.
            value.to_r
          end
        end

        def assert_finite!(value)
          return if value.is_a?(Rational) || value.finite?

          raise ArgumentError, "Audioproxy option value #{value} is not a finite number"
        end

        # scaled is the value times 10**MAX_DECIMALS, exactly. Negative zero
        # collapses on the way in: -0.0 scales to plain 0.
        def render_scaled(scaled)
          sign = scaled.negative? ? "-" : ""
          whole, fraction = scaled.abs.divmod(10 ** MAX_DECIMALS)
          return "#{sign}#{whole}" if fraction.zero?

          "#{sign}#{whole}.#{format("%0#{MAX_DECIMALS}d", fraction).sub(/0+\z/, "")}"
        end
    end
  end
end
