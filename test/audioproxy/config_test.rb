require "test_helper"

class Audioproxy::ConfigTest < ActiveSupport::TestCase
  setup do
    @config = Audioproxy::Config.new
  end

  test "defaults are inert" do
    assert_nil @config.endpoint
    assert_nil @config.key
    assert_nil @config.salt
    assert_equal false, @config.unsigned
    assert_equal({}, @config.default_options)
  end

  test "valid hex key is decoded to raw bytes" do
    @config.key = "00112233445566778899AABBCCDDEEFF00112233445566778899AABBCCDDEEFF"

    assert_equal 32, @config.key.bytesize
    assert_equal [ 0x00, 0x11, 0x22, 0x33 ], @config.key.bytes.first(4)
    assert_equal [ 0xCC, 0xDD, 0xEE, 0xFF ], @config.key.bytes.last(4)
  end

  test "lowercase hex decodes identically to uppercase" do
    @config.salt = "ffeeddccbbaa99887766554433221100"
    lowercase = @config.salt
    @config.salt = "FFEEDDCCBBAA99887766554433221100"

    assert_equal lowercase, @config.salt
  end

  test "non-hex key raises naming the attribute" do
    error = assert_raises(ArgumentError) { @config.key = "not-hex" }

    assert_match(/key/, error.message)
  end

  test "odd-length salt raises naming the attribute" do
    error = assert_raises(ArgumentError) { @config.salt = "abc" }

    assert_match(/salt/, error.message)
  end

  test "empty hex string raises" do
    assert_raises(ArgumentError) { @config.key = "" }
  end

  test "nil key and salt are allowed for unsigned mode" do
    @config.key = nil
    @config.salt = nil

    assert_nil @config.key
    assert_nil @config.salt
  end

  test "endpoint with a path prefix is accepted" do
    @config.endpoint = "https://cdn.example.com/audio"

    assert_equal "https://cdn.example.com/audio", @config.endpoint
  end

  test "plain http endpoint is accepted" do
    @config.endpoint = "http://localhost:4000"

    assert_equal "http://localhost:4000", @config.endpoint
  end

  test "trailing slash is normalized away" do
    @config.endpoint = "https://audio.example.com/"

    assert_equal "https://audio.example.com", @config.endpoint
  end

  test "schemeless endpoint is rejected" do
    error = assert_raises(ArgumentError) { @config.endpoint = "audio.example.com" }

    assert_match(/endpoint/, error.message)
  end

  test "non-http scheme is rejected" do
    assert_raises(ArgumentError) { @config.endpoint = "ftp://audio.example.com" }
  end

  test "endpoint carrying userinfo is rejected so credentials cannot leak into URLs" do
    error = assert_raises(ArgumentError) { @config.endpoint = "https://user:pass@audio.example.com" }

    assert_match(/userinfo/, error.message)
    refute_match(/pass/, error.message)
  end

  test "endpoint carrying a query is rejected" do
    assert_raises(ArgumentError) { @config.endpoint = "https://audio.example.com?foo=bar" }
    assert_raises(ArgumentError) { @config.endpoint = "https://cdn.example.com/audio?foo=bar" }
  end

  test "endpoint carrying a fragment is rejected" do
    assert_raises(ArgumentError) { @config.endpoint = "https://audio.example.com#frag" }
  end

  test "non-String endpoint is rejected by class, not coerced" do
    error = assert_raises(ArgumentError) { @config.endpoint = :"https://audio.example.com" }

    assert_match(/String/, error.message)
  end

  # String.try_convert honours the implicit to_str protocol, and URI::Generic
  # defines to_str. Passing a URI object is a reasonable thing to do, so this
  # is deliberate rather than a hole in the type check.
  test "a URI object is accepted, since it converts implicitly to a String" do
    @config.endpoint = URI.parse("https://audio.example.com")

    assert_equal "https://audio.example.com", @config.endpoint
  end

  test "non-String key is rejected by class, not coerced" do
    error = assert_raises(ArgumentError) { @config.key = 1122 }

    assert_match(/Integer/, error.message)
  end

  test "hostless endpoint is rejected" do
    assert_raises(ArgumentError) { @config.endpoint = "https://" }
  end

  test "default_options are stored as given" do
    @config.default_options = { raw: "f:opus" }

    assert_equal({ raw: "f:opus" }, @config.default_options)
  end

  test "default_options string keys are normalized to symbols" do
    @config.default_options = { "raw" => "f:opus" }

    assert_equal({ raw: "f:opus" }, @config.default_options)
  end

  test "default_options rejects a non-Hash rather than ignoring it" do
    error = assert_raises(ArgumentError) { @config.default_options = "f:opus" }

    assert_match(/Hash/, error.message)
  end

  test "default_options rejects unsupported keys so a typo cannot be dropped" do
    error = assert_raises(ArgumentError) { @config.default_options = { format: "opus" } }

    assert_match(/format/, error.message)
  end

  test "default_options rejects keys that are neither String nor Symbol" do
    assert_raises(ArgumentError) { @config.default_options = { 1 => "f:opus" } }
  end

  test "default_options rejects a key that merely quacks like a Symbol" do
    quacker = Object.new
    def quacker.to_sym = :raw

    assert_raises(ArgumentError) { @config.default_options = { quacker => "f:opus" } }
  end

  test "default_options accepts nil as empty" do
    @config.default_options = nil

    assert_equal({}, @config.default_options)
  end

  test "Audioproxy.configure yields and stores the global config" do
    original = Audioproxy.config

    begin
      Audioproxy.config = Audioproxy::Config.new
      returned = Audioproxy.configure do |c|
        c.endpoint = "https://audio.example.com"
        c.key = "aabb"
        c.salt = "ccdd"
        c.unsigned = true
      end

      assert_same Audioproxy.config, returned
      assert_equal "https://audio.example.com", Audioproxy.config.endpoint
      assert_equal [ 0xAA, 0xBB ], Audioproxy.config.key.bytes
      assert_equal [ 0xCC, 0xDD ], Audioproxy.config.salt.bytes
      assert_equal true, Audioproxy.config.unsigned
    ensure
      Audioproxy.config = original
    end
  end
end
