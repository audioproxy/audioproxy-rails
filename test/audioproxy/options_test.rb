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

  test "an opaque value carrying a slash raises instead of shifting the path" do
    error = assert_raises(ArgumentError) { Options.segment(:dl, "album/track.mp3") }

    assert_match(%r{'/'}, error.message)
  end

  test "an empty value raises rather than signing a blank segment" do
    assert_raises(ArgumentError) { Options.segment(:dl, "") }
  end

  test "a nil value raises rather than being dropped" do
    assert_raises(ArgumentError) { Options.segment(:br, nil) }
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
