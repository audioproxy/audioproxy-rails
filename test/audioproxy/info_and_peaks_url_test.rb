require "test_helper"
require_relative "../fixtures/signature_vectors"

class Audioproxy::InfoAndPeaksUrlTest < ActiveSupport::TestCase
  ENDPOINT = "https://audio.example.com".freeze
  SOURCE = "local://previews/track.wav".freeze
  ENCODED = Base64.urlsafe_encode64(SOURCE, padding: false).freeze
  EXPIRES_AT = 1893456000

  setup do
    @config = Audioproxy::Config.new
    @config.endpoint = ENDPOINT
    @config.key = SignatureVectors::KEY_HEX
    @config.salt = SignatureVectors::SALT_HEX
    @builder = Audioproxy::UrlBuilder.new(@config)
  end

  # --- info: shape and signing -----------------------------------------------

  test "an info URL has no options segment between signature and source" do
    url = @builder.info_url(SOURCE)
    signature = @builder.sign("/info/enc/#{ENCODED}")

    assert_equal "#{ENDPOINT}/#{signature}/info/enc/#{ENCODED}", url
  end

  test "an endpoint's trailing slash is normalized for info URLs too" do
    @config.endpoint = "#{ENDPOINT}/"

    assert_match %r{\A#{ENDPOINT}/[A-Za-z0-9_-]{43}/info/enc/}o, @builder.info_url(SOURCE)
  end

  # D8: the builder emits enc/, never plain/, so the vector is met at the
  # builder's signing path rather than by round-tripping a whole URL.
  test "the builder signs the info shape as the proxy's known-answer vector does" do
    vector = SignatureVectors::VECTORS.find { |v| v[:rest_of_path].start_with?("/info/") }

    assert_equal "/info/plain/s3://b/k.wav", vector[:rest_of_path]
    assert_equal vector[:signature], @builder.sign(vector[:rest_of_path])
  end

  test "Audioproxy.info_url uses the global configuration" do
    with_global_config do
      assert_equal @builder.info_url(SOURCE), Audioproxy.info_url(SOURCE)
    end
  end

  # --- info: no options, no defaults, no expiry -------------------------------

  # expires_at is both a builder keyword and exp's alias; it gets the expiry
  # message instead, covered below.
  test "info rejects every typed option key, in both spellings" do
    keys = Audioproxy::Options::KEYS + Audioproxy::Options::ALIASES.values - Audioproxy::UrlBuilder::EXPIRY_KEYWORDS
    keys.uniq.each do |key|
      error = assert_raises(ArgumentError, "#{key} was accepted") { @builder.info_url(SOURCE, key => 1) }

      assert_match(/422/, error.message)
    end
  end

  test "info rejects raw:" do
    error = assert_raises(ArgumentError) { @builder.info_url(SOURCE, raw: "f:opus") }

    assert_match(/raw/, error.message)
  end

  test "info rejects an unknown keyword rather than dropping it" do
    assert_raises(ArgumentError) { @builder.info_url(SOURCE, nonsense: 1) }
  end

  test "typed defaults never reach an info URL" do
    @config.default_options = { f: :opus, br: 96 }

    url = @builder.info_url(SOURCE)

    assert_includes url, "/info/enc/"
    refute_includes url, "f:opus"
    refute_includes url, "br:96"
  end

  test "a raw default never reaches an info URL" do
    @config.default_options = { raw: "f:opus/br:96" }

    assert_equal "#{ENDPOINT}/#{@builder.sign("/info/enc/#{ENCODED}")}/info/enc/#{ENCODED}",
      @builder.info_url(SOURCE)
  end

  test "config.expires_in never reaches an info URL" do
    @config.expires_in = 1.hour

    refute_includes @builder.info_url(SOURCE), "exp:"
  end

  test "a per-call expiry on info raises, whichever keyword" do
    [ { expires_in: 1.hour }, { expires_at: Time.at(EXPIRES_AT) } ].each do |expiry|
      error = assert_raises(ArgumentError) { @builder.info_url(SOURCE, **expiry) }

      assert_match(/expir/, error.message)
      assert_match(/info/, error.message)
    end
  end

  test "an explicit nil expiry on info is the URL info builds anyway" do
    @config.expires_in = 1.hour

    assert_equal @builder.info_url(SOURCE), @builder.info_url(SOURCE, expires_in: nil)
    assert_equal @builder.info_url(SOURCE), @builder.info_url(SOURCE, expires_at: nil)
  end

  # --- info: builder overrides ------------------------------------------------

  test "info honours a per-call endpoint without touching the config" do
    url = @builder.info_url(SOURCE, endpoint: "https://audio-eu.example.com")

    assert url.start_with?("https://audio-eu.example.com/")
    assert_equal ENDPOINT, @config.endpoint
  end

  test "an unsigned info URL needs no key or salt" do
    config = Audioproxy::Config.new
    config.endpoint = ENDPOINT

    assert_equal "#{ENDPOINT}/insecure/info/enc/#{ENCODED}",
      Audioproxy::UrlBuilder.new(config).info_url(SOURCE, unsigned: true)
  end

  test "an info URL still raises for a missing source" do
    assert_raises(ArgumentError) { @builder.info_url(nil) }
  end

  # --- peaks: shape -----------------------------------------------------------

  test "a minimal peaks URL carries f:peaks alone" do
    assert_includes @builder.peaks_url(SOURCE), "/f:peaks/enc/#{ENCODED}"
  end

  test "peaks options render after the format" do
    assert_includes @builder.peaks_url(SOURCE, pts: 800, pk_fmt: :dat), "/f:peaks/pts:800/pk_fmt:dat/enc/"
  end

  test "pk_bits reaches a peaks URL in either spelling" do
    assert_includes @builder.peaks_url(SOURCE, pk_bits: 8), "/f:peaks/pk_bits:8/enc/"
    assert_equal @builder.peaks_url(SOURCE, pk_bits: 8), @builder.peaks_url(SOURCE, peak_bits: 8)
  end

  test "time-domain options render under their aliases" do
    assert_includes @builder.peaks_url(SOURCE, trim: [ 12.5, 30 ], channels: 2), "/f:peaks/t:12.5:30/ch:2/enc/"
  end

  test "Audioproxy.peaks_url uses the global configuration" do
    with_global_config do
      assert_equal @builder.peaks_url(SOURCE, pts: 800), Audioproxy.peaks_url(SOURCE, pts: 800)
    end
  end

  # D5: the proxy materializes its own ch default into the cache key.
  test "no channel default is materialized" do
    refute_includes @builder.peaks_url(SOURCE, pts: 400), "ch:"
  end

  # --- peaks: the format ------------------------------------------------------

  test "a redundant peaks format changes nothing, wherever it is written" do
    [ { f: :peaks }, { format: :peaks }, { "f" => "peaks" } ].each do |format|
      assert_equal @builder.peaks_url(SOURCE, pts: 800), @builder.peaks_url(SOURCE, pts: 800, **format)
      assert_equal @builder.peaks_url(SOURCE, pts: 800), @builder.peaks_url(SOURCE, **format, pts: 800)
    end
  end

  test "a conflicting format raises naming both, as written" do
    error = assert_raises(ArgumentError) { @builder.peaks_url(SOURCE, format: :opus) }

    assert_match(/peaks/, error.message)
    assert_match(/format: :opus/, error.message)
  end

  test "a nil format is a conflict, not an omission" do
    assert_raises(ArgumentError) { @builder.peaks_url(SOURCE, f: nil) }
  end

  # --- peaks: the allowlist ---------------------------------------------------

  REFUSED = (Audioproxy::Options::KEYS - Audioproxy::Options::PEAKS_KEYS - %i[f exp]).freeze

  test "the refused set is the encoding options the proxy refuses for peaks" do
    assert_equal %i[bd br q sr], REFUSED.sort
  end

  REFUSED.each do |key|
    [ key, Audioproxy::Options::ALIASES[key] ].each do |spelling|
      test "peaks refuse #{spelling}, naming it as written and what peaks accept" do
        error = assert_raises(ArgumentError) { @builder.peaks_url(SOURCE, spelling => 96) }

        assert_match(/\b#{spelling}\b/, error.message)
        assert_match(/pts, pk_fmt, pk_bits/, error.message)
      end
    end
  end

  test "exp: on peaks points at the expiry keywords, not the allowlist" do
    error = assert_raises(ArgumentError) { @builder.peaks_url(SOURCE, exp: EXPIRES_AT) }

    assert_match(/peaks_url does not take exp:/, error.message)
    assert_match(/expires_in/, error.message)
  end

  test "an unknown key on peaks raises" do
    assert_raises(ArgumentError) { @builder.peaks_url(SOURCE, bit_rate: 96) }
  end

  test "raw: on peaks raises, pointing at url_for" do
    error = assert_raises(ArgumentError) { @builder.peaks_url(SOURCE, raw: "pts:800") }

    assert_match(/raw/, error.message)
    assert_match(/url_for/, error.message)
  end

  test "both spellings of one peaks option still raise" do
    assert_raises(ArgumentError) { @builder.peaks_url(SOURCE, pts: 800, peak_count: 400) }
  end

  # --- peaks: defaults (D10) --------------------------------------------------

  test "audio-only defaults are skipped" do
    @config.default_options = { f: :opus, br: 96 }

    url = @builder.peaks_url(SOURCE)

    assert_includes url, "/f:peaks/enc/"
    refute_includes url, "opus"
    refute_includes url, "br:96"
  end

  test "allowlisted defaults apply, so a waveform follows normalized audio" do
    @config.default_options = { f: :opus, norm: :ebu }

    assert_includes @builder.peaks_url(SOURCE, pts: 800), "/f:peaks/norm:ebu/pts:800/enc/"
  end

  test "an aliased allowlisted default applies" do
    @config.default_options = { format: :opus, normalize: :ebu, bitrate: 96 }

    assert_includes @builder.peaks_url(SOURCE), "/f:peaks/norm:ebu/enc/"
  end

  test "a per-call key overrides an allowlisted default in place" do
    @config.default_options = { norm: :ebu, pts: 800 }

    assert_includes @builder.peaks_url(SOURCE, peak_count: 400), "/f:peaks/norm:ebu/pts:400/enc/"
  end

  test "a raw default is skipped" do
    @config.default_options = { raw: "f:opus/br:96" }

    assert_includes @builder.peaks_url(SOURCE), "/f:peaks/enc/"
  end

  # --- peaks: builder keywords ------------------------------------------------

  test "an expiry applies to peaks exactly as url_for appends it" do
    assert_includes @builder.peaks_url(SOURCE, pts: 800, expires_at: EXPIRES_AT),
      "/f:peaks/pts:800/exp:#{EXPIRES_AT}/enc/"
  end

  test "config.expires_in applies to peaks, and nil opts one out" do
    @config.expires_in = 1.hour

    assert_includes @builder.peaks_url(SOURCE), "/exp:"
    refute_includes @builder.peaks_url(SOURCE, expires_in: nil), "exp:"
  end

  test "peaks honour endpoint: and unsigned:" do
    url = @builder.peaks_url(SOURCE, endpoint: "https://audio-eu.example.com", unsigned: true)

    assert_equal "https://audio-eu.example.com/insecure/f:peaks/enc/#{ENCODED}", url
  end

  # --- url_for is untouched ---------------------------------------------------

  # Generated on main before this change, by url_for as it stood then. If any
  # of these move, the shared assembly this change extracted has changed a
  # variant URL, which it must not.
  test "url_for emits the same bytes it did before info and peaks existed" do
    assert_equal "https://audio.example.com/HsPQylKjJLXvsYYXw6jjxGWaYD8U_BJOAEFXGm0FMQQ/f:mp3/enc/bG9jYWw6Ly9hLndhdg",
      @builder.url_for("local://a.wav")
    assert_equal "https://audio.example.com/EConNLhhsbbs-8zZaSXYVGK1BECaqX2InF0nW4MD15w/f:opus/br:96/t:12.5:30/enc/czM6Ly9tYXN0ZXJzL3BpZWNlLndhdg",
      @builder.url_for("s3://masters/piece.wav", f: :opus, br: 96, t: [ 12.5, 30 ])
    assert_equal "https://audio.example.com/h-suM64-rrV81xAHbc7p103uFufJUGjLnKgZdL81Ej8/f:opus/br:96/exp:1893456000/enc/bG9jYWw6Ly9hLndhdg",
      @builder.url_for("local://a.wav", raw: "f:opus/br:96", expires_at: EXPIRES_AT)

    @config.default_options = { format: :opus, bitrate: 96 }
    assert_equal "https://audio.example.com/_vm5b4qjwVctwdfcL0Y0GNQ-ZqwNq_Zew7cLK_qfBUs/f:opus/br:96/pts:800/exp:1893456000/enc/bG9jYWw6Ly9hLndhdg",
      @builder.url_for("local://a.wav", pts: 800, expires_at: EXPIRES_AT)
  end
  private
    def with_global_config
      original = Audioproxy.config
      Audioproxy.config = @config
      yield
    ensure
      Audioproxy.config = original
    end
end
