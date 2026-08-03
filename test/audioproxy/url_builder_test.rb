require "test_helper"
require_relative "../fixtures/signature_vectors"

class Audioproxy::UrlBuilderTest < ActiveSupport::TestCase
  ENDPOINT = "https://audio.example.com".freeze

  setup do
    @config = Audioproxy::Config.new
    @config.endpoint = ENDPOINT
    @config.key = SignatureVectors::KEY_HEX
    @config.salt = SignatureVectors::SALT_HEX
    @builder = Audioproxy::UrlBuilder.new(@config)
  end

  # --- signing -------------------------------------------------------------

  SignatureVectors::VECTORS.each_with_index do |vector, index|
    test "known-answer vector #{index + 1} matches the proxy's reference signer" do
      assert_equal vector[:signature], @builder.sign(vector[:rest_of_path])
    end
  end

  test "signatures are 43 unpadded base64url characters" do
    [ "/f:mp3/enc/abc", "/info/plain/local://a.wav", "/f:opus/br:96/enc/#{"x" * 200}" ].each do |path|
      signature = @builder.sign(path)

      assert_equal 43, signature.length, "#{path.inspect} produced #{signature.inspect}"
      assert_match(/\A[A-Za-z0-9_-]+\z/, signature)
      refute_includes signature, "="
    end
  end

  test "signing a path without a leading slash raises" do
    assert_raises(ArgumentError) { @builder.sign("f:opus/plain/local://a.wav") }
  end

  test "signing a path with non-ASCII bytes does not raise on encoding" do
    assert_equal 43, @builder.sign("/f:mp3/plain/local://tänze.wav").length
  end

  test "signing without a key raises a configuration error naming key" do
    @config.key = nil

    error = assert_raises(Audioproxy::ConfigurationError) { @builder.sign("/f:mp3/enc/abc") }

    assert_match(/key/, error.message)
  end

  test "signing without a salt raises a configuration error naming salt" do
    @config.salt = nil

    error = assert_raises(Audioproxy::ConfigurationError) { @builder.sign("/f:mp3/enc/abc") }

    assert_match(/salt/, error.message)
  end

  # --- URL shape -----------------------------------------------------------

  test "full URL shape" do
    url = @builder.url_for("local://previews/track.wav", raw: "f:opus/br:96")

    encoded = base64url("local://previews/track.wav")
    rest = "/f:opus/br:96/enc/#{encoded}"
    expected_signature = reference_signature(rest)

    assert_equal "#{ENDPOINT}/#{expected_signature}#{rest}", url
  end

  test "the signature in a built URL covers exactly the path after it" do
    url = @builder.url_for("local://a.wav", raw: "f:mp3")

    signature, rest = url.delete_prefix("#{ENDPOINT}/").split("/", 2)

    assert_equal signature, reference_signature("/#{rest}")
  end

  # --- source encoding -----------------------------------------------------

  test "sources with spaces are base64url encoded, never percent-escaped" do
    url = @builder.url_for("s3://masters/a track.wav", raw: "f:mp3")

    assert_includes url, "enc/#{base64url("s3://masters/a track.wav")}"
    refute_includes url, "%20"
    refute_includes url, " "
  end

  test "awkward sources round-trip through the enc segment" do
    [
      "s3://masters/a track.wav",
      "https://origin.example.com/audio?token=abc&x=1",
      "local://already%20escaped.wav",
      "local://tänze/übung.wav",
      "local://plus+and/slash.wav"
    ].each do |source|
      segment = @builder.url_for(source, raw: "f:mp3").split("/enc/").last

      assert_match(/\A[A-Za-z0-9_-]+\z/, segment, "#{source.inspect} produced #{segment.inspect}")
      refute_includes segment, "="
      assert_equal source, decode_base64url(segment)
    end
  end

  test "plain sources are never emitted" do
    refute_includes @builder.url_for("local://a.wav"), "/plain/"
  end

  test "a nil source raises instead of signing an empty enc segment" do
    error = assert_raises(ArgumentError) { @builder.url_for(nil) }

    assert_match(/source/, error.message)
  end

  test "an empty source raises" do
    assert_raises(ArgumentError) { @builder.url_for("") }
  end

  test "a non-String source raises rather than being stringified" do
    error = assert_raises(ArgumentError) { @builder.url_for(123) }

    assert_match(/Integer/, error.message)
  end

  # --- options -------------------------------------------------------------

  test "raw options are used verbatim" do
    url = @builder.url_for("local://a.wav", raw: "f:opus/t:12.5:30")

    assert_includes url, "/f:opus/t:12.5:30/enc/"
  end

  test "configured default options apply when no raw is given" do
    @config.default_options = { raw: "f:opus" }

    assert_includes @builder.url_for("local://a.wav"), "/f:opus/enc/"
  end

  test "per-call raw options override configured defaults" do
    @config.default_options = { raw: "f:opus" }

    url = @builder.url_for("local://a.wav", raw: "f:mp3/br:128")

    assert_includes url, "/f:mp3/br:128/enc/"
    refute_includes url, "f:opus"
  end

  test "falls back to f:mp3 with no options and no defaults" do
    assert_includes @builder.url_for("local://a.wav"), "/f:mp3/enc/"
  end

  test "an empty raw string falls back to f:mp3" do
    assert_includes @builder.url_for("local://a.wav", raw: ""), "/f:mp3/enc/"
  end

  test "a whitespace-only raw string falls back to f:mp3 rather than signing blanks" do
    assert_includes @builder.url_for("local://a.wav", raw: "   "), "/f:mp3/enc/"
  end

  test "string-keyed default options are honoured, not silently dropped" do
    @config.default_options = { "raw" => "f:opus" }

    assert_includes @builder.url_for("local://a.wav"), "/f:opus/enc/"
  end

  test "raw options bracketed by a slash raise instead of signing a doubled separator" do
    [ "/f:opus", "f:opus/", "/f:opus/" ].each do |bracketed|
      error = assert_raises(ArgumentError, "expected #{bracketed.inspect} to raise") do
        @builder.url_for("local://a.wav", raw: bracketed)
      end

      assert_match(%r{'/'}, error.message)
    end
  end

  test "raw options are stripped of surrounding whitespace" do
    assert_includes @builder.url_for("local://a.wav", raw: " f:opus "), "/f:opus/enc/"
  end

  test "raw: false raises rather than silently falling back" do
    @config.default_options = { raw: "f:opus" }

    error = assert_raises(ArgumentError) { @builder.url_for("local://a.wav", raw: false) }

    assert_match(/FalseClass/, error.message)
  end

  # --- unsigned ------------------------------------------------------------

  test "per-call unsigned emits the literal insecure segment" do
    url = @builder.url_for("local://a.wav", unsigned: true)

    assert_equal "#{ENDPOINT}/insecure/f:mp3/enc/#{base64url("local://a.wav")}", url
  end

  test "config-level unsigned needs no key or salt" do
    @config.key = nil
    @config.salt = nil
    @config.unsigned = true

    assert_includes @builder.url_for("local://a.wav"), "/insecure/"
  end

  test "per-call unsigned false overrides config-level unsigned" do
    @config.unsigned = true

    refute_includes @builder.url_for("local://a.wav", unsigned: false), "insecure"
  end

  test "building a signed URL without a key raises naming key" do
    @config.key = nil

    error = assert_raises(Audioproxy::ConfigurationError) { @builder.url_for("local://a.wav") }

    assert_match(/key/, error.message)
  end

  # --- endpoint ------------------------------------------------------------

  test "per-call endpoint override does not mutate the global config" do
    url = @builder.url_for("local://a.wav", endpoint: "https://audio-eu.example.com")

    assert url.start_with?("https://audio-eu.example.com/"), url
    assert_equal ENDPOINT, @config.endpoint
  end

  test "per-call endpoint is validated like a configured one" do
    assert_raises(ArgumentError) { @builder.url_for("local://a.wav", endpoint: "audio-eu.example.com") }
  end

  test "building without any endpoint raises a configuration error" do
    @config.endpoint = nil

    assert_raises(Audioproxy::ConfigurationError) { @builder.url_for("local://a.wav") }
  end

  test "a path-prefixed endpoint signs identically to a bare one" do
    bare = @builder.url_for("local://previews/track.wav", raw: "f:opus/br:96")
    prefixed = @builder.url_for("local://previews/track.wav", raw: "f:opus/br:96", endpoint: "https://cdn.example.com/audio")

    assert_equal bare.delete_prefix(ENDPOINT), prefixed.delete_prefix("https://cdn.example.com/audio")
    assert prefixed.start_with?("https://cdn.example.com/audio/"), prefixed
  end

  test "a trailing-slash endpoint produces no double slash" do
    url = @builder.url_for("local://a.wav", endpoint: "https://audio.example.com/")

    refute_includes url.delete_prefix("https://"), "//"
  end

  # --- module entry point --------------------------------------------------

  test "Audioproxy.url_for delegates to the global config" do
    original = Audioproxy.config

    begin
      Audioproxy.config = @config

      assert_equal @builder.url_for("local://a.wav", raw: "f:opus"),
        Audioproxy.url_for("local://a.wav", raw: "f:opus")
    ensure
      Audioproxy.config = original
    end
  end

  private
    # Deliberately spelled out rather than calling the builder, so the tests
    # assert against the algorithm and not against the implementation. That
    # extends to the base64url step below: the builder uses
    # Base64.urlsafe_encode64, so computing the expected value by the same call
    # would only prove the method agrees with itself. The pack/tr/delete spelling
    # is an independent route to the same bytes — keep it that way.
    def reference_signature(rest_of_path)
      key = [ SignatureVectors::KEY_HEX ].pack("H*")
      salt = [ SignatureVectors::SALT_HEX ].pack("H*")

      base64url OpenSSL::HMAC.digest("SHA256", key, salt + rest_of_path.b)
    end

    def base64url(bytes)
      [ bytes ].pack("m0").tr("+/", "-_").delete("=")
    end

    # urlsafe_decode64 accepts unpadded input, so the hand-rolled padding
    # arithmetic this replaces is not worth keeping. Independence does not
    # matter here: this only round-trips the source, it does not pin a contract.
    def decode_base64url(segment)
      Base64.urlsafe_decode64(segment).force_encoding(Encoding::UTF_8)
    end
end
