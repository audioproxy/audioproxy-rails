require "test_helper"
require_relative "../fixtures/signature_vectors"

# Expiry is exercised through UrlBuilder rather than against Audioproxy::Expiry
# directly, because the thing that has to be right is the rendered segment: the
# proxy answers a wrong one with 410 or 422 at request time, nowhere near the
# call. Every arithmetic assertion below names the exact bytes.
class Audioproxy::ExpiryTest < ActiveSupport::TestCase
  ENDPOINT = "https://audio.example.com".freeze

  # 2026-01-01T00:00:00Z, a round number so every expected segment below can be
  # read as arithmetic rather than taken on trust.
  FROZEN = Time.at(1767225600).utc

  setup do
    @config = Audioproxy::Config.new
    @config.endpoint = ENDPOINT
    @config.key = SignatureVectors::KEY_HEX
    @config.salt = SignatureVectors::SALT_HEX
    @builder = Audioproxy::UrlBuilder.new(@config)
  end

  # The options segment of a built URL: everything between the signature and
  # the source, so an assertion covers position as well as value.
  def options_of(url)
    url.delete_prefix("#{ENDPOINT}/").split("/")[1..-3].join("/")
  end

  def build(...)
    options_of(@builder.url_for("local://a.wav", ...))
  end

  # --- 3.1 arithmetic ------------------------------------------------------

  test "expires_in accepts a duration, an Integer and every duration unit" do
    travel_to FROZEN do
      assert_equal "f:mp3/exp:1767229200", build(expires_in: 1.hour)
      assert_equal "f:mp3/exp:1767225690", build(expires_in: 90)
      assert_equal "f:mp3/exp:1767227400", build(expires_in: 30.minutes)
      assert_equal "f:mp3/exp:1767312000", build(expires_in: 1.day)
      assert_equal "f:mp3/exp:1767225601", build(expires_in: 1.second)
    end
  end

  test "expires_at accepts Time, DateTime, TimeWithZone and an Integer" do
    travel_to FROZEN do
      expected = "f:mp3/exp:1767229200"
      instant = Time.at(1767229200).utc

      assert_equal expected, build(expires_at: instant)
      assert_equal expected, build(expires_at: instant.to_datetime)
      assert_equal expected, build(expires_at: instant.in_time_zone("Europe/Vienna"))
      assert_equal expected, build(expires_at: 1767229200)
    end
  end

  # A TimeWithZone is the single most likely Rails input, and the type check
  # that admits it is load-order-sensitive: `case/when Time` matches one only
  # because ActiveSupport patches Time.===, which this gem never requires. This
  # suite runs under full Rails, so it cannot see that difference — see the
  # comment in Expiry.unix_seconds, and signer_isolation_test.rb for the shape
  # of a test that could. Pinned here for the behaviour, not the mechanism.
  test "a TimeWithZone is read as the instant it stands for, not its wall clock" do
    travel_to FROZEN do
      vienna = Time.at(1767229200).in_time_zone("Europe/Vienna")
      tokyo = Time.at(1767229200).in_time_zone("Asia/Tokyo")

      assert_equal "f:mp3/exp:1767229200", build(expires_at: vienna)
      assert_equal build(expires_at: vienna), build(expires_at: tokyo)
    end
  end

  # 0.5.hours is a Duration whose #value is the Float 1800.0, not an Integer.
  # It lands on a whole second, so it is accepted — the whole-seconds rule is
  # about the value, not about its class. The neighbouring raise (1.5.seconds,
  # #value 1.5) is asserted below; this is the other side of that line.
  test "a Duration with a whole-valued Float is accepted" do
    travel_to FROZEN do
      assert_equal "f:mp3/exp:1767227400", build(expires_in: 0.5.hours)
      assert_equal build(expires_in: 30.minutes), build(expires_in: 0.5.hours)
    end
  end

  # The past-check refuses `expires_at == now`; one second later must pass, or
  # the guard is off by one in the direction that silently rejects live URLs.
  test "one second past now is accepted, and now itself is not" do
    travel_to FROZEN do
      assert_equal "f:mp3/exp:1767225601", build(expires_at: FROZEN + 1.second)
      assert_raises(ArgumentError) { build(expires_at: FROZEN) }
    end
  end

  # A DateTime carries its own offset, and to_time must read the instant rather
  # than the wall clock. A UTC-only fixture would pass either way.
  test "a non-UTC DateTime is read as the instant it names" do
    travel_to FROZEN do
      # 03:00+02:00 is 01:00Z, which is 1767229200. Read as a wall clock and
      # stamped as UTC it would be 1767236400, seven thousand seconds out.
      vienna = DateTime.new(2026, 1, 1, 3, 0, 0, "+02:00")

      assert_equal "f:mp3/exp:1767229200", build(expires_at: vienna)
      assert_equal build(expires_at: Time.at(1767229200).utc), build(expires_at: vienna)
    end
  end

  test "sub-second precision on expires_at truncates rather than rounding up" do
    travel_to FROZEN do
      # Truncating moves the expiry at most one second early, which is the
      # fail-safe direction; rounding up would hand out a URL that outlives
      # what the caller asked for.
      assert_equal "f:mp3/exp:1767229200", build(expires_at: Time.at(1767229200.9).utc)
    end
  end

  test "the expiry segment goes last and leaves the variant prefix untouched" do
    travel_to FROZEN do
      assert_equal "f:opus/br:96", build(f: :opus, br: 96)
      assert_equal "f:opus/br:96/exp:1767229200", build(f: :opus, br: 96, expires_in: 1.hour)
    end
  end

  test "the whole URL differs only in the expiry, so the variant is one variant" do
    travel_to FROZEN do
      eternal = @builder.url_for("local://a.wav", f: :opus)
      expiring = @builder.url_for("local://a.wav", f: :opus, expires_in: 1.hour)

      refute_equal eternal, expiring
      assert_equal "f:opus", options_of(eternal)
      assert_equal "f:opus/exp:1767229200", options_of(expiring)
    end
  end

  test "no expiry anywhere leaves the URL byte-identical to before this slice" do
    travel_to FROZEN do
      assert_equal "f:mp3", build
      assert_equal "f:opus/br:96", build(f: :opus, br: 96)
      assert_equal "f:opus/br:96", build(raw: "f:opus/br:96")
    end
  end

  # --- raw: composition (D3) -----------------------------------------------

  test "an expiry composes with raw options rather than being dropped" do
    travel_to FROZEN do
      assert_equal "f:opus/br:96/exp:1767229200",
        build(raw: "f:opus/br:96", expires_in: 1.hour)
    end
  end

  test "a raw string that already carries exp: raises when an expiry applies" do
    travel_to FROZEN do
      error = assert_raises(ArgumentError) do
        build(raw: "f:opus/exp:1767229200", expires_in: 1.hour)
      end

      assert_match(/exp:/, error.message)
      assert_match(/expires_in: nil/, error.message)
    end
  end

  test "a raw string carrying exp: passes through when no expiry applies" do
    travel_to FROZEN do
      assert_equal "f:opus/exp:1767229200", build(raw: "f:opus/exp:1767229200")
    end
  end

  # The config default is the case the caller cannot see at the call site, so
  # it is the one that most needs the guard above.
  test "a configured default collides with a raw exp: too" do
    @config.expires_in = 1.hour

    travel_to FROZEN do
      assert_raises(ArgumentError) { build(raw: "f:opus/exp:1767229200") }
    end
  end

  # --- 3.2 every raise path ------------------------------------------------

  test "both keywords together raise and produce no URL" do
    error = assert_raises(ArgumentError) do
      build(expires_in: 1.hour, expires_at: 1.hour.from_now)
    end

    assert_match(/expires_in/, error.message)
    assert_match(/expires_at/, error.message)
  end

  test "both keywords raise even when both are the nil opt-out" do
    # Two spellings of one concept in one call is the same ambiguity raw: and
    # typed keys raise on, and it raises there regardless of value too.
    assert_raises(ArgumentError) { build(expires_in: nil, expires_at: nil) }
  end

  test "a non-positive expires_in raises" do
    [ 0, -1, -1.hour, 0.seconds ].each do |window|
      error = assert_raises(ArgumentError, "expected #{window.inspect} to raise") do
        build(expires_in: window)
      end

      assert_match(/positive/, error.message)
    end
  end

  test "an expires_at at or before now raises rather than minting a dead URL" do
    travel_to FROZEN do
      [ FROZEN, FROZEN - 1.second, FROZEN - 1.day, 1, 0, -1 ].each do |instant|
        error = assert_raises(ArgumentError, "expected #{instant.inspect} to raise") do
          build(expires_at: instant)
        end

        assert_match(/future/, error.message)
      end
    end
  end

  test "a fractional duration raises rather than truncating silently" do
    error = assert_raises(ArgumentError) { build(expires_in: 1.5.seconds) }

    assert_match(/whole number of seconds/, error.message)
    assert_match(/round explicitly/, error.message)
  end

  test "an uncoercible expires_in type raises" do
    [ "1h", 3600.0, :hour, Time.now, nil.to_a ].each do |window|
      assert_raises(ArgumentError, "expected #{window.inspect} to raise") do
        build(expires_in: window)
      end
    end
  end

  test "an uncoercible expires_at type raises" do
    [ "2026-01-01", 3600.0, :soon, 1.hour ].each do |instant|
      assert_raises(ArgumentError, "expected #{instant.inspect} to raise") do
        build(expires_at: instant)
      end
    end
  end

  # A Date's to_time is local midnight, so the same call means a different
  # instant on every machine that renders it.
  test "a Date raises and the message says why" do
    error = assert_raises(ArgumentError) { build(expires_at: Date.new(2026, 6, 1)) }

    assert_match(/Date/, error.message)
    assert_match(/midnight/, error.message)
  end

  # The millisecond typo — some_time.to_i * 1000 — is otherwise a clean-looking
  # URL and a 422 at request time.
  test "a timestamp past the proxy's bound raises" do
    max = Audioproxy::Options::MAX_EXPIRES_AT

    assert_equal 253_402_300_799, max, "the bound is copied from the proxy's @max_expires_at"

    travel_to FROZEN do
      assert_equal "f:mp3/exp:#{max}", build(expires_at: max)

      error = assert_raises(ArgumentError) { build(expires_at: max + 1) }
      assert_match(/milliseconds/, error.message)

      assert_raises(ArgumentError) { build(expires_at: 1767229200 * 1000) }

      # An out-of-range window overflows the same bound, but the caller wrote a
      # duration, so the millisecond advice would name a mistake they did not
      # make.
      window = assert_raises(ArgumentError) { build(expires_in: max) }

      assert_match(/window of #{max} seconds/, window.message)
      refute_match(/milliseconds/, window.message)
    end
  end

  # --- D1: exp is not reachable as an ordinary option -----------------------

  test "exp as an option key raises and names the keywords instead" do
    error = assert_raises(ArgumentError) { build(exp: 1767229200) }

    assert_match(/expires_in/, error.message)
    assert_match(/expires_at/, error.message)
  end

  test "exp in default_options raises at assignment" do
    [ { exp: 1767229200 }, { expires_at: 1767229200 }, { "exp" => 1767229200 } ].each do |defaults|
      error = assert_raises(ArgumentError, "expected #{defaults.inspect} to raise") do
        @config.default_options = defaults
      end

      assert_match(/expires_in/, error.message)
    end
  end

  test "Options renders exp only as an Integer" do
    assert_equal "exp:1767225600", Audioproxy::Options.segment(:exp, 1767225600)
    assert_equal "exp:1767225600", Audioproxy::Options.segment(:expires_at, 1767225600)

    [ 1767225600.0, "1767225600", :now, 1.hour ].each do |value|
      assert_raises(ArgumentError, "expected #{value.inspect} to raise") do
        Audioproxy::Options.segment(:exp, value)
      end
    end
  end

  # --- 3.3 the default / override / opt-out matrix --------------------------

  test "a configured default applies to every URL" do
    @config.expires_in = 1.hour

    travel_to FROZEN do
      assert_equal "f:mp3/exp:1767229200", build
      assert_equal "f:opus/br:96/exp:1767229200", build(f: :opus, br: 96)
      assert_equal "f:opus/exp:1767229200", build(raw: "f:opus")
    end
  end

  test "a per-call expires_in overrides the configured default" do
    @config.expires_in = 1.hour

    travel_to FROZEN do
      assert_equal "f:mp3/exp:1767225690", build(expires_in: 90)
      assert_equal "f:mp3/exp:1767226500", build(expires_in: 15.minutes)
    end
  end

  test "a per-call expires_at overrides the configured default and is not a conflict" do
    @config.expires_in = 1.hour

    travel_to FROZEN do
      assert_equal "f:mp3/exp:1767312000", build(expires_at: Time.at(1767312000).utc)
    end
  end

  test "a per-call nil opts one URL out of the configured default" do
    @config.expires_in = 1.hour

    travel_to FROZEN do
      assert_equal "f:mp3", build(expires_in: nil)
      assert_equal "f:mp3", build(expires_at: nil)
      assert_equal "f:opus/br:96", build(f: :opus, br: 96, expires_in: nil)
    end
  end

  test "no configured default means no expiry" do
    assert_nil @config.expires_in

    travel_to FROZEN do
      assert_equal "f:mp3", build
    end
  end

  test "config expires_in validates at assignment, with the same rules as the keyword" do
    @config.expires_in = 1.hour
    assert_equal 3600, @config.expires_in

    @config.expires_in = 90
    assert_equal 90, @config.expires_in

    @config.expires_in = nil
    assert_nil @config.expires_in

    [ 0, -1, "1h", 1.5.seconds, 3600.0, Time.now ].each do |value|
      assert_raises(ArgumentError, "expected #{value.inspect} to raise") do
        @config.expires_in = value
      end
    end
  end

  test "the configured default is measured from each call, not from boot" do
    @config.expires_in = 1.hour

    first = travel_to(FROZEN) { build }
    second = travel_to(FROZEN + 10.minutes) { build }

    assert_equal "f:mp3/exp:1767229200", first
    assert_equal "f:mp3/exp:1767229800", second
  end

  # --- interactions with the other per-call overrides ----------------------

  # Unsigned mode replaces the signature segment, not the path after it, so an
  # expiry has to survive it. The proxy still enforces exp under
  # AP_ALLOW_INSECURE, which is what makes a dropped one here a live URL that
  # was supposed to be short-lived.
  test "an expiry survives unsigned mode and a per-call endpoint" do
    travel_to FROZEN do
      unsigned = @builder.url_for("local://a.wav", unsigned: true, expires_in: 1.hour)

      assert_equal "#{ENDPOINT}/insecure/f:mp3/exp:1767229200/enc/bG9jYWw6Ly9hLndhdg", unsigned

      elsewhere = @builder.url_for("local://a.wav", endpoint: "https://eu.example.com", expires_in: 1.hour)

      assert elsewhere.start_with?("https://eu.example.com/")
      assert_equal "f:mp3/exp:1767229200", options_of(elsewhere.sub("https://eu.example.com", ENDPOINT))
    end
  end

  # --- the signature covers it ---------------------------------------------

  # exp is signed path bytes on the proxy side, so altering it must invalidate
  # the URL exactly as altering any other segment does.
  test "the signature covers the expiry segment" do
    travel_to FROZEN do
      url = @builder.url_for("local://a.wav", expires_in: 1.hour)
      signature = url.delete_prefix("#{ENDPOINT}/").split("/").first

      assert_equal signature, @builder.sign("/f:mp3/exp:1767229200/enc/#{Base64.urlsafe_encode64("local://a.wav", padding: false)}")
      refute_equal signature, @builder.sign("/f:mp3/exp:1767229201/enc/#{Base64.urlsafe_encode64("local://a.wav", padding: false)}")
    end
  end
end
