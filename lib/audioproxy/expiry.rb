require "date"
require "active_support/duration"
require "audioproxy/options"

module Audioproxy
  # Turns the two Rails-shaped expiry spellings — +expires_in: 1.hour+ and
  # +expires_at: some_time+ — into the single Integer of unix seconds the
  # proxy's +exp+ option takes.
  #
  # Every method here raises rather than coercing. The proxy answers a URL whose
  # +exp+ has passed with 410 and one out of bounds with 422, both at request
  # time and neither anywhere near the call that built it, so an input this
  # module cannot read exactly is an error at the call site (D5).
  module Expiry
    # Sentinel for "this keyword was not passed". nil cannot do the job: it is
    # the documented per-call opt-out from a configured default (D6).
    UNSET = Object.new.freeze

    class << self
      # The +exp+ value for one URL, or nil for no expiry at all. +now+ is
      # supplied by the caller and read once per URL, so the arithmetic below
      # and the past-check cannot straddle a second boundary (D4).
      def timestamp(expires_in:, expires_at:, default_expires_in:, now:)
        if given?(expires_in) && given?(expires_at)
          raise ArgumentError,
            "Audioproxy url_for takes either expires_in: or expires_at:, not both; " \
            "expires_in: is a window from now, expires_at: is the instant itself"
        end

        return at(expires_at, now: now) if given?(expires_at)
        return within(expires_in, now: now, source: "url_for expires_in:") if given?(expires_in)
        return nil if default_expires_in.nil?

        # Already validated at assignment, so this is arithmetic and nothing
        # else — but it still goes through the bound check that `within` runs.
        within(default_expires_in, now: now, source: "config expires_in")
      end

      # A window of whole positive seconds, as an Integer. Shared by the keyword
      # and by Config#expires_in= so that a value accepted at boot is exactly a
      # value accepted per call.
      def seconds(value, source:)
        case value
        # #value is the exact number of seconds the Duration stands for (3600
        # for 1.hour), and it stays an Integer where the caller wrote one, so a
        # far-future window does not lose digits to a double on the way past.
        when ActiveSupport::Duration then whole_seconds(value, value.value, source: source)
        when Integer then value
        else
          raise ArgumentError,
            "Audioproxy #{source} must be an ActiveSupport::Duration or an Integer of seconds, " \
            "got #{value.inspect}"
        end.tap do |seconds|
          unless seconds.positive?
            raise ArgumentError,
              "Audioproxy #{source} must be a positive number of seconds, got #{value.inspect}; " \
              "a window of #{seconds} mints a URL that is already expired"
          end
        end
      end

      private
        def given?(value)
          !value.equal?(UNSET)
        end

        def within(value, now:, source:)
          return nil if value.nil?

          window = seconds(value, source: source)

          bounded(now + window, source: source, window: window)
        end

        def at(value, now:)
          return nil if value.nil?

          seconds = bounded(unix_seconds(value), source: "url_for expires_at:")

          # The proxy's own check is `now > exp`, so the second exp names is
          # still served and only a strictly-past value is dead on arrival.
          # Refusing equality too costs one second and makes the rule statable
          # as "expires_at: must be in the future" (D5).
          unless seconds > now
            raise ArgumentError,
              "Audioproxy url_for expires_at: must be in the future, got #{value.inspect} " \
              "(#{seconds}, and it is now #{now}); the proxy would answer that URL with 410"
          end

          seconds
        end

        # Time, DateTime and ActiveSupport::TimeWithZone, or an Integer already
        # in unix seconds.
        #
        # is_a? rather than case/when, and the reason is narrower than the one
        # Options gives for Duration. TimeWithZone overrides is_a? to answer
        # truthfully about what it stands for, and Module#=== ignores that
        # override — but ActiveSupport patches Time.=== to cover the gap
        # (core_ext/time/calculations.rb), so under full Rails a case/when Time
        # matches a TimeWithZone after all.
        #
        # It matches only where that core_ext is loaded, and this file does not
        # require it: after a bare `require "audioproxy"`, Time.=== is still
        # Module's. Since url_for is documented as usable with no Rails loaded,
        # case/when here would accept a TimeWithZone in an app and reject it in
        # a plain Ruby script. is_a? is TimeWithZone's own override and needs
        # nothing else loaded, so it answers the same in both.
        #
        # Date is not on the list. Date#to_time is local midnight, so the same
        # `expires_at: Date.tomorrow` means a different instant on every machine
        # that renders it.
        def unix_seconds(value)
          return value if value.is_a?(Integer)

          unless value.is_a?(Time) || value.is_a?(DateTime)
            raise ArgumentError,
              "Audioproxy url_for expires_at: must be a Time, DateTime, " \
              "ActiveSupport::TimeWithZone or an Integer of unix seconds, got #{value.class}" \
              "#{" (a Date is local midnight, which is a different instant per machine; pass a Time)" if value.is_a?(Date)}"
          end

          # Truncates sub-second, which moves the expiry at most one second
          # earlier — the fail-safe direction.
          value.to_time.to_i
        end

        # The proxy caps exp and 422s past it, which is where the millisecond
        # typo (`some_time.to_i * 1000`) lands: a clean-looking URL that never
        # works.
        #
        # +window+ is set only on the expires_in: path, where the caller wrote a
        # duration rather than a timestamp — advising them about milliseconds
        # there would name a mistake they did not make.
        def bounded(seconds, source:, window: nil)
          if seconds > Options::MAX_EXPIRES_AT
            raise ArgumentError,
              "Audioproxy #{source} produced #{seconds}, past the proxy's limit of " \
              "#{Options::MAX_EXPIRES_AT} (9999-12-31T23:59:59Z); " \
              "#{window ? "a window of #{window} seconds reaches past the year 9999" : "unix seconds, not milliseconds"}"
          end

          seconds
        end

        # A Duration whose total is not a whole number of seconds has no exact
        # rendering here, and truncating one silently is the class of thing this
        # gem raises about everywhere else — see Options.format_decimal.
        def whole_seconds(value, total, source:)
          unless total == total.to_i
            raise ArgumentError,
              "Audioproxy #{source} must be a whole number of seconds, got #{value.inspect} " \
              "(#{total}); round explicitly at the call site if that is what you mean"
          end

          total.to_i
        end
    end
  end
end
