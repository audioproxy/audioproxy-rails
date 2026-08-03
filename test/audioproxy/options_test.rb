require "test_helper"

class Audioproxy::OptionsTest < ActiveSupport::TestCase
  Options = Audioproxy::Options

  # --- the key table -------------------------------------------------------

  # One example per proxy key, so a key dropped from the table fails here
  # rather than as a 422 at request time.
  KEY_EXAMPLES = {
    bd: [ 24, "bd:24" ],
    br: [ 96, "br:96" ],
    cb: [ "v2", "cb:v2" ],
    ch: [ 1, "ch:1" ],
    dl: [ "piece.mp3", "dl:piece.mp3" ],
    f: [ :opus, "f:opus" ],
    fade: [ [ 1, 2 ], "fade:1:2" ],
    gain: [ -2.5, "gain:-2.5" ],
    norm: [ :ebu, "norm:ebu" ],
    pk_fmt: [ :json, "pk_fmt:json" ],
    pts: [ 800, "pts:800" ],
    q: [ 5, "q:5" ],
    sr: [ 44100, "sr:44100" ],
    t: [ 12.5, "t:12.5" ]
  }.freeze

  test "the key table covers exactly the proxy's fourteen keys" do
    assert_equal 14, Options::KEYS.size
    assert_equal Options::KEYS.sort, KEY_EXAMPLES.keys.sort
  end

  KEY_EXAMPLES.each do |key, (value, expected)|
    test "#{key} renders as #{expected}" do
      assert_equal expected, Options.segment(key, value)
    end
  end

  test "string keys are accepted alongside symbols" do
    assert_equal "f:opus", Options.segment("f", :opus)
  end

  test "an unknown key raises and lists the known keys" do
    error = assert_raises(ArgumentError) { Options.segment(:bt, 96) }

    assert_match(/bt/, error.message)
    assert_match(/br/, error.message)
    assert_match(/pk_fmt/, error.message)
  end

  # --- spelled-out aliases -------------------------------------------------

  test "the alias table is total over the key table" do
    assert_equal Options::KEYS.sort, Options::ALIASES.keys.sort
    assert_equal Options::ALIASES.size, Options::ALIASES.values.uniq.size
  end

  # A change-detector, deliberately: it pins the table so an alias cannot be
  # renamed without someone editing this literal too. It does NOT check the
  # server — that comparison was made against ../audioproxy's Options struct
  # once, and is recorded in D2; the server is not a dependency of this suite
  # and cannot be read from CI. Renaming an alias means redoing that check by
  # hand, not just updating this hash.
  test "the alias table is pinned against silent renaming" do
    assert_equal(
      {
        f: :format, br: :bitrate, q: :quality, sr: :sample_rate, ch: :channels,
        bd: :bit_depth, t: :trim, fade: :fade, gain: :gain, norm: :normalize,
        pts: :peak_count, pk_fmt: :peak_format, dl: :download, cb: :cache_buster
      },
      Options::ALIASES
    )
  end

  KEY_EXAMPLES.each do |key, (value, expected)|
    test "the #{Options::ALIASES[key]} alias renders as #{expected}" do
      assert_equal expected, Options.segment(Options::ALIASES[key], value)
    end
  end

  test "an alias is accepted as a String too" do
    assert_equal "br:96", Options.segment("bitrate", 96)
  end

  test "aliases and canonical keys mix in one call" do
    assert_equal "f:opus/br:96", Options.render({ format: :opus, br: 96 })
  end

  test "an aliased key keeps its position rather than moving" do
    assert_equal "t:30/f:opus/br:96", Options.render({ trim: 30, f: :opus, bitrate: 96 })
  end

  test "multi-part options keep their array form under an alias" do
    assert_equal "norm:ebu:-16:-1.5:11", Options.segment(:normalize, [ :ebu, -16, -1.5, 11 ])
    assert_equal "t:12.5:30", Options.segment(:trim, [ 12.5, 30 ])
  end

  test "both spellings of one option raise, naming both" do
    error = assert_raises(ArgumentError) { Options.render({ bitrate: 96, br: 128 }) }

    assert_match(/bitrate/, error.message)
    assert_match(/br/, error.message)
  end

  # "as fade and fade" names the collision twice and tells the caller nothing.
  # Worst on the self-aliasing keys, where the two spellings are always the
  # same word and only the String/Symbol form differs.
  test "the conflict message distinguishes a String key from a Symbol key" do
    error = assert_raises(ArgumentError) { Options.render({ "fade" => 1, fade: 2 }) }

    assert_match(/"fade"/, error.message)
    assert_match(/:fade/, error.message)
  end

  test "a near-miss alias still raises, and the message names both vocabularies" do
    error = assert_raises(ArgumentError) { Options.segment(:bit_rate, 96) }

    assert_match(/bit_rate/, error.message)
    assert_match(/pk_fmt/, error.message)
    assert_match(/alias/, error.message)
  end

  test "resolve rewrites onto canonical keys and leaves the rest alone" do
    assert_equal({ f: :opus, br: 96, t: 30 }, Options.resolve({ format: :opus, br: 96, trim: 30 }))
    assert_equal({ raw: "f:opus" }, Options.resolve({ raw: "f:opus" }))
  end

  test "symbols and strings render alike" do
    assert_equal Options.segment(:f, :opus), Options.segment(:f, "opus")
  end

  # --- multi-part options --------------------------------------------------

  test "trim with start and duration" do
    assert_equal "t:12.5:30", Options.segment(:t, [ 12.5, 30 ])
  end

  test "trim with start only, as a scalar" do
    assert_equal "t:12.5", Options.segment(:t, 12.5)
  end

  test "a single-element array is the scalar form" do
    assert_equal "t:12.5", Options.segment(:t, [ 12.5 ])
  end

  test "fade takes in and out" do
    assert_equal "fade:1:2", Options.segment(:fade, [ 1, 2 ])
  end

  test "EBU normalization with targets" do
    assert_equal "norm:ebu:-16:-1.5:11", Options.segment(:norm, [ :ebu, -16, -1.5, 11 ])
  end

  test "array elements go through the number formatter" do
    assert_equal "t:30:1.5", Options.segment(:t, [ 30.0, 1.500 ])
    assert_raises(ArgumentError) { Options.segment(:t, [ 0.1234, 30 ]) }
  end

  test "an array on a single-part key raises rather than rendering its inspect" do
    error = assert_raises(ArgumentError) { Options.segment(:f, [ :opus, :mp3 ]) }

    assert_match(/single value/, error.message)
  end

  test "an empty array raises" do
    assert_raises(ArgumentError) { Options.segment(:t, []) }
  end

  # --- opaque keys ---------------------------------------------------------

  test "opaque values render verbatim, without number formatting" do
    assert_equal "cb:v2", Options.segment(:cb, "v2")
    assert_equal "cb:1.2340", Options.segment(:cb, "1.2340")
    assert_equal "dl:piece-final.mp3", Options.segment(:dl, "piece-final.mp3")
  end

  # Opaque does not mean unchecked: the builder supplies the separators, and a
  # value carrying one invents a segment or a part. '?' and '#' are worse — a
  # browser ends the path there, so the proxy receives less than was signed and
  # 403s at request time, nowhere near this call.
  test "an opaque value carrying a separator raises instead of shifting the path" do
    {
      "album/track.mp3" => "/",
      "a:b.mp3" => ":",
      "track?raw=1" => "?",
      "track#2" => "#",
      "two words.mp3" => " ",
      "track\n.mp3" => "\n"
    }.each do |value, offender|
      error = assert_raises(ArgumentError, "expected #{value.inspect} to raise") do
        Options.segment(:dl, value)
      end

      assert_match(/must not contain #{Regexp.escape(offender.inspect)}/, error.message)
    end
  end

  test "a separator in a formatted value raises too" do
    assert_raises(ArgumentError) { Options.segment(:f, :"opus/mp3") }
    assert_raises(ArgumentError) { Options.segment(:f, "op us") }
  end

  test "an empty value raises rather than signing a blank segment" do
    assert_raises(ArgumentError) { Options.segment(:dl, "") }
    assert_raises(ArgumentError) { Options.segment(:f, "") }
  end

  test "an empty part inside a multi-part value raises" do
    # "t::30" reads as a whole value, not as a missing one.
    assert_raises(ArgumentError) { Options.segment(:t, [ "", 30 ]) }
    assert_raises(ArgumentError) { Options.segment(:fade, [ 1, "" ]) }
    assert_raises(ArgumentError) { Options.segment(:norm, [ :ebu, nil ]) }
  end

  test "a nil value raises rather than being dropped" do
    assert_raises(ArgumentError) { Options.segment(:br, nil) }
  end

  # --- durations on the time-valued keys -----------------------------------

  test "a duration renders as its number of seconds" do
    assert_equal "t:30", Options.segment(:t, 30.seconds)
    assert_equal "t:60", Options.segment(:t, 1.minute)
  end

  test "durations inside a multi-part value" do
    assert_equal "fade:1.5:2", Options.segment(:fade, [ 1.5.seconds, 2.seconds ])
  end

  test "durations and numbers mix in one array" do
    assert_equal "t:12.5:60", Options.segment(:t, [ 12.5, 1.minute ])
  end

  # 0.3.seconds is the case that decides how a Duration is unwrapped: #to_r
  # gives the double's true value, which the three-decimal cap rejects, while
  # the identical t: 0.3 renders (D6).
  test "sub-second durations render like the numbers they wrap" do
    assert_equal "t:0.5", Options.segment(:t, 0.5.seconds)
    assert_equal "t:0.3", Options.segment(:t, 0.3.seconds)
    assert_equal "t:0.001", Options.segment(:t, 0.001.seconds)
    assert_equal Options.segment(:t, 0.3), Options.segment(:t, 0.3.seconds)
  end

  test "a duration needing more than three decimals raises, as the number does" do
    assert_raises(ArgumentError) { Options.segment(:t, 0.1234.seconds) }
  end

  test "a duration on a key whose value is not seconds raises rather than rendering" do
    error = assert_raises(ArgumentError) { Options.segment(:br, 3.seconds) }

    assert_match(/duration/, error.message)
    assert_match(/t, fade/, error.message)
  end

  test "a duration on an opaque key raises too" do
    assert_raises(ArgumentError) { Options.segment(:cb, 3.seconds) }
    assert_raises(ArgumentError) { Options.segment(:dl, 3.seconds) }
  end

  test "durations reach the time keys under their aliases too" do
    assert_equal "t:30", Options.segment(:trim, 30.seconds)
  end

  # Calendar-variable units resolve through Duration's own average-seconds
  # definition rather than a rule invented here. Absurd as a trim, and nothing
  # stops them — the same stance the gem takes on br: 999999.
  test "calendar durations render through Duration's own definition" do
    assert_equal "t:#{1.month.value}", Options.segment(:t, 1.month)
  end

  # --- rendering a whole segment string ------------------------------------

  test "segments join with slashes in the order given" do
    assert_equal "f:opus/br:96/t:12.5:30",
      Options.render({ f: :opus, br: 96, t: [ 12.5, 30 ] })
  end

  test "caller order is preserved, not sorted" do
    assert_equal "t:30/f:opus/br:96", Options.render({ t: 30, f: :opus, br: 96 })
  end

  test "rendering an empty hash produces an empty string" do
    assert_equal "", Options.render({})
  end

  # --- no domain validation ------------------------------------------------

  test "out-of-domain values render; the proxy is the validator" do
    assert_equal "br:999999", Options.segment(:br, 999999)
    assert_equal "ch:99", Options.segment(:ch, 99)
    assert_equal "f:flac-but-not-really", Options.segment(:f, "flac-but-not-really")
  end

  test "cross-key rules are not enforced client-side" do
    assert_equal "br:96/q:5", Options.render({ br: 96, q: 5 })
  end
end
