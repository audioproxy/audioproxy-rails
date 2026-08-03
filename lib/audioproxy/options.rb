require "active_support/duration"

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

    # A spelled-out spelling for each canonical key, for call sites that would
    # rather read than decode. Total over KEYS, so "does this key have an alias"
    # never has two answers: +fade+ and +gain+ are already words and alias to
    # themselves. The names are the proxy's own where it has one — its Options
    # struct calls pts +peak_count+ and pk_fmt +peak_format+ — so this is one
    # vocabulary spelled twice, not a second vocabulary (D2).
    ALIASES = {
      f: :format,
      br: :bitrate,
      q: :quality,
      sr: :sample_rate,
      ch: :channels,
      bd: :bit_depth,
      t: :trim,
      fade: :fade,
      gain: :gain,
      norm: :normalize,
      pts: :peak_count,
      pk_fmt: :peak_format,
      dl: :download,
      cb: :cache_buster
    }.freeze

    # Every accepted spelling to the canonical key it renders as. Canonical
    # keys map to themselves, so resolution is one lookup rather than a
    # conditional.
    CANONICAL = ALIASES.each_with_object({}) { |(key, spelled), table| table[spelled] = key }
      .merge(KEYS.to_h { |key| [ key, key ] })
      .freeze

    # Keys whose grammar takes colon-separated parts: +t:START[:DURATION]+,
    # +fade:IN[:OUT]+, +norm:ebu[:I[:TP[:LRA]]]+.
    MULTI_PART_KEYS = %i[t fade norm].freeze

    # Keys whose values *are* a number of seconds, and so may be written as an
    # ActiveSupport::Duration (D6).
    TIME_KEYS = %i[t fade].freeze

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
        resolve(options).map { |key, value| segment(key, value) }.join("/")
      end

      # Rewrites a key => value Hash onto the canonical short keys, so that
      # everything downstream — rendering, ordering, the defaults merge — sees
      # one vocabulary and is unaware aliases exist (D1). Insertion order is
      # preserved, so an aliased key keeps its slot. Unrecognized keys pass
      # through untouched, to be reported by +segment+ against the key table
      # rather than by a second, thinner error here.
      def resolve(options)
        spellings = {}

        options.each_with_object({}) do |(key, value), resolved|
          canonical = CANONICAL.fetch(symbolize(key), key)

          # Ruby's keyword collection keeps both spellings, and picking a winner
          # by position would make the URL depend on argument order in a way
          # nothing else here does (D4).
          if (first = spellings[canonical])
            raise ArgumentError,
              "Audioproxy option #{canonical} was given twice, as #{first} and #{key}; " \
              "each option takes one spelling per call"
          end
          spellings[canonical] = key

          resolved[canonical] = value
        end
      end

      # Renders one +key:value+ segment. The key may be canonical or an alias.
      def segment(key, value)
        key = CANONICAL.fetch(symbolize(key)) do |unknown|
          raise ArgumentError,
            "unknown Audioproxy option #{unknown.inspect}; known keys are #{KEYS.join(", ")}, " \
            "each also accepted as its spelled-out alias (#{ALIASES[:br]}, #{ALIASES[:sr]}, #{ALIASES[:pk_fmt]}, …)"
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
          # An explicit clause, because +case value when Numeric+ does not match
          # a Duration: it overrides is_a? to answer true for Numeric, but
          # Module#=== performs the real type check and ignores the override.
          # Without this, t: 30.seconds is rejected as "not a number" by
          # something that says it is one.
          return render_duration(key, value) if value.is_a?(ActiveSupport::Duration)
          return format_number(value) unless OPAQUE_KEYS.include?(key)

          case value
          when String then value
          when Symbol, Numeric then format_number(value)
          else
            raise ArgumentError, "Audioproxy option #{key}: must be a String, Symbol or number, got #{value.class}"
          end
        end

        # A Duration is the Rails spelling of a number of seconds, so it is
        # accepted where the value *is* seconds and refused everywhere else:
        # br: 3.seconds rendering br:3 would be a valid-looking URL for the
        # wrong variant, which is the failure this gem exists to prevent (D6).
        def render_duration(key, value)
          unless TIME_KEYS.include?(key)
            raise ArgumentError,
              "Audioproxy option #{key}: does not take a duration, got #{value.inspect}; " \
              "only #{TIME_KEYS.join(", ")} take an ActiveSupport::Duration, because only their values are seconds"
          end

          # #value is the number the caller wrote (30 for 30.seconds, 0.3 for
          # 0.3.seconds, 60 for 1.minute), so it goes through exactly the
          # formatting that number would and renders the same bytes. #to_r is
          # the wrong door: for 0.3.seconds it yields the double's true value,
          # which the three-decimal cap then rejects, while a plain t: 0.3
          # renders — Float goes through Rational(value.to_s) for that reason.
          format_number(value.value)
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
