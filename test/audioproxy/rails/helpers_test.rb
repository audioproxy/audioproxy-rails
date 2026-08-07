require "test_helper"

# Everything here goes through `view`, a real ActionView::Base, rather than
# through `tests Audioproxy::Rails::Helpers`. Including the module into the test
# case would prove the methods work while saying nothing about whether the
# railtie's on_load(:action_view) hook ever fired.
class Audioproxy::Rails::HelpersTest < ActionView::TestCase
  include AttachedRecordings

  SOURCE = "local://previews/track.wav".freeze

  test "the railtie mixed the helpers into ActionView" do
    assert_includes ActionView::Base.ancestors, Audioproxy::Rails::Helpers
  end

  # --- audioproxy_url ------------------------------------------------------

  test "audioproxy_url returns exactly what Audioproxy.url_for returns" do
    assert_equal Audioproxy.url_for(SOURCE), view.audioproxy_url(SOURCE)
  end

  test "audioproxy_url passes options straight through" do
    assert_equal Audioproxy.url_for(SOURCE, raw: "f:opus"),
      view.audioproxy_url(SOURCE, raw: "f:opus")
    assert_equal Audioproxy.url_for(SOURCE, f: "opus", br: 96),
      view.audioproxy_url(SOURCE, f: "opus", br: 96)
    assert_equal Audioproxy.url_for(SOURCE, unsigned: true),
      view.audioproxy_url(SOURCE, unsigned: true)
  end

  test "audioproxy_url lets the core's errors through" do
    assert_raises(ArgumentError) { view.audioproxy_url(SOURCE, nonsense: 1) }
    assert_raises(ArgumentError) { view.audioproxy_url(nil) }
  end

  # --- audioproxy_audio_tag ------------------------------------------------

  test "audioproxy_audio_tag renders an audio tag around the proxy URL" do
    tag = view.audioproxy_audio_tag(SOURCE, raw: "f:opus")

    assert_equal %(<audio src="#{Audioproxy.url_for(SOURCE, raw: "f:opus")}"></audio>), tag
  end

  test "the html: hash becomes tag attributes" do
    tag = view.audioproxy_audio_tag(SOURCE, raw: "f:opus", html: { controls: true, class: "player" })

    assert_includes tag, %(src="#{Audioproxy.url_for(SOURCE, raw: "f:opus")}")
    assert_includes tag, "controls=\"controls\""
    assert_includes tag, %(class="player")
  end

  test "proxy options never appear as tag attributes" do
    tag = view.audioproxy_audio_tag(SOURCE, raw: "f:opus")

    refute_includes tag, "raw="
    refute_includes tag, "f:opus\""
  end

  # The seam cuts both ways, and that is the whole point of it: the two
  # namespaces never merge, so neither one can absorb a key meant for the other.
  test "a proxy option renders into the URL, never onto the tag" do
    tag = view.audioproxy_audio_tag(SOURCE, download: "take-1.mp3")

    assert_includes tag, %(src="#{Audioproxy.url_for(SOURCE, download: "take-1.mp3")}")
    refute_includes tag, "download="
  end

  test "a tag attribute passed as a proxy option raises instead of being rendered" do
    error = assert_raises(ArgumentError) { view.audioproxy_audio_tag(SOURCE, controls: true) }

    assert_match(/unknown Audioproxy option/, error.message)
  end

  test "html: attributes are not sent to the proxy" do
    tag = view.audioproxy_audio_tag(SOURCE, html: { preload: "none" })

    assert_includes tag, %(preload="none")
    assert_includes tag, %(src="#{Audioproxy.url_for(SOURCE)}")
  end

  # --- default_options through the helpers ---------------------------------
  #
  # The core covers the merge itself; what is unexercised is whether the
  # helpers hand options over intact enough for it to happen at all. These
  # mutate the process-global config, so each one puts it back.

  def with_default_options(defaults)
    previous = Audioproxy.config.default_options
    Audioproxy.config.default_options = defaults
    yield
  ensure
    Audioproxy.config.default_options = previous
  end

  test "configured defaults reach a helper called with no options" do
    with_default_options(format: "opus", bitrate: 96) do
      assert_includes view.audioproxy_url(SOURCE), "/f:opus/br:96/"
      assert_includes view.audioproxy_audio_tag(SOURCE), "/f:opus/br:96/"
    end
  end

  test "a per-call option merges over a defaulted one rather than repeating it" do
    with_default_options(format: "opus", bitrate: 96) do
      url = view.audioproxy_url(SOURCE, bitrate: 128)

      assert_includes url, "/f:opus/br:128/"
      refute_includes url, "br:96"
    end
  end

  # The alias layer collapses a spelled-out default and a canonical per-call key
  # into one segment. Through the helper it has to survive two keyword splats.
  test "an aliased default and a canonical per-call key stay one segment" do
    with_default_options(bitrate: 96) do
      url = view.audioproxy_url(SOURCE, br: 128)

      assert_includes url, "/br:128/"
      refute_includes url, "br:96"
    end
  end

  test "a per-call raw: replaces the defaults entirely" do
    with_default_options(format: "opus", bitrate: 96) do
      url = view.audioproxy_url(SOURCE, raw: "f:flac")

      assert_includes url, "/f:flac/"
      refute_includes url, "opus"
    end
  end

  test "defaults land in the src while html: still lands on the tag" do
    with_default_options(format: "opus") do
      tag = view.audioproxy_audio_tag(SOURCE, html: { controls: true })

      assert_includes tag, "/f:opus/"
      assert_includes tag, %(controls="controls")
      refute_includes tag, "format="
    end
  end

  test "html: attributes are never treated as options against the defaults" do
    with_default_options(format: "opus") do
      assert_equal view.audioproxy_url(SOURCE),
        view.audioproxy_audio_tag(SOURCE, html: { class: "player" })[/src="([^"]+)"/, 1]
    end
  end

  test "html: must be a Hash" do
    error = assert_raises(ArgumentError) { view.audioproxy_audio_tag(SOURCE, html: "controls") }

    assert_match(/html: must be a Hash/, error.message)
  end

  test "audioproxy_audio_tag without html: renders a bare tag" do
    assert_equal %(<audio src="#{Audioproxy.url_for(SOURCE)}"></audio>),
      view.audioproxy_audio_tag(SOURCE)
  end

  # --- ActiveStorage end to end --------------------------------------------
  #
  # Everything else in this file hands the helpers a source string. These start
  # from a real attachment on the dummy app's Disk service and go all the way
  # to a signed URL, which is the only place the whole chain — railtie
  # registration, unwrapping, disk layout, encoding, signing — is exercised as
  # one thing.

  test "the railtie registered the blob resolver with the core" do
    assert_equal Audioproxy::Rails::BlobResolver, Audioproxy.source_resolver
  end

  test "an attachment reaches audioproxy_url as its resolved source" do
    recording = attached_recording

    assert_equal Audioproxy.url_for("local://#{disk_path_for(recording)}"),
      view.audioproxy_url(recording.audio)
  end

  test "a blob through audioproxy_audio_tag renders a signed src" do
    recording = attached_recording

    tag = view.audioproxy_audio_tag(recording.audio, format: "opus", html: { controls: true })
    src = tag[/src="([^"]+)"/, 1]
    signature = src.delete_prefix("#{Audioproxy.config.endpoint}/").split("/").first

    assert_includes tag, %(controls="controls")
    assert_includes src, "/f:opus/enc/"
    refute_equal Audioproxy::UrlBuilder::INSECURE_SEGMENT, signature
    assert_match(/\A[A-Za-z0-9_-]{43}\z/, signature)
    assert_equal "local://#{disk_path_for(recording)}",
      Base64.urlsafe_decode64(src.split("/enc/").last)
  end

  test "an unattached attachment raises out of the helper" do
    assert_raises(Audioproxy::UnattachedError) { view.audioproxy_url(Recording.new.audio) }
  end

  # --- audioproxy_preload_link_tag -----------------------------------------

  test "audioproxy_preload_link_tag renders a preload link around the proxy URL" do
    tag = view.audioproxy_preload_link_tag(SOURCE, raw: "f:opus")

    assert_includes tag, %(rel="preload")
    assert_includes tag, %(href="#{Audioproxy.url_for(SOURCE, raw: "f:opus")}")
  end

  # ActionView reads `as` off the source's extension, and the encoded source
  # segment never has one, so an unsupplied `as` is not a default but a bug.
  test "the preload hint declares an audio destination" do
    assert_includes view.audioproxy_preload_link_tag(SOURCE), %(as="audio")
  end

  test "html: as overrides the audio destination exactly once" do
    tag = view.audioproxy_preload_link_tag(SOURCE, html: { as: "fetch" })

    assert_includes tag, %(as="fetch")
    refute_includes tag, %(as="audio")
    assert_equal 1, tag.scan(/ as=/).size
  end

  # A string key has to win too, or it renders alongside the symbol default.
  test "a string as key overrides the audio destination" do
    tag = view.audioproxy_preload_link_tag(SOURCE, html: { "as" => "fetch" })

    assert_includes tag, %(as="fetch")
    assert_equal 1, tag.scan(/ as=/).size
  end

  # nil, false and "" all reach ActionView's extension inference, which has no
  # extension to read, and the attribute is dropped or emitted empty. Either way
  # the tag looks like a preload and does nothing, so it raises instead.
  test "a blank as is refused rather than emitted" do
    [ nil, false, "" ].each do |blank|
      error = assert_raises(ArgumentError) { view.audioproxy_preload_link_tag(SOURCE, html: { as: blank }) }

      assert_match(/must name a fetch destination/, error.message)
    end
  end

  test "a blank string as key is refused too" do
    assert_raises(ArgumentError) { view.audioproxy_preload_link_tag(SOURCE, html: { "as" => nil }) }
  end

  # ActionView renders this one as "anonymous" and audio_tag renders it as
  # "true", so the pair would disagree and the browser would fetch twice.
  test "crossorigin: true is refused because the two helpers render it differently" do
    error = assert_raises(ArgumentError) { view.audioproxy_preload_link_tag(SOURCE, html: { crossorigin: true }) }

    assert_match(/crossorigin: must be a String/, error.message)
    assert_includes view.audioproxy_audio_tag(SOURCE, html: { crossorigin: true }), %(crossorigin="true")
  end

  test "an explicit crossorigin string renders the same on both helpers" do
    assert_includes view.audioproxy_preload_link_tag(SOURCE, html: { crossorigin: "anonymous" }),
      %(crossorigin="anonymous")
    assert_includes view.audioproxy_audio_tag(SOURCE, html: { crossorigin: "anonymous" }),
      %(crossorigin="anonymous")
  end

  # Not a supported combination — as: "font" on an audio URL is a caller error —
  # but ActionView injects crossorigin for it, so the helper's "no crossorigin"
  # rule has this one documented exception. Pinned so it stays deliberate.
  test "as: font reaches ActionView's implicit crossorigin" do
    assert_includes view.audioproxy_preload_link_tag(SOURCE, html: { as: "font" }),
      %(crossorigin="anonymous")
  end

  # Matching audioproxy_audio_tag, which sets none: a preload whose crossorigin
  # disagrees with the element consuming it fetches the variant twice.
  test "no crossorigin unless asked for" do
    refute_includes view.audioproxy_preload_link_tag(SOURCE), "crossorigin"
    assert_includes view.audioproxy_preload_link_tag(SOURCE, html: { crossorigin: "anonymous" }),
      %(crossorigin="anonymous")
  end

  test "html: attributes become link attributes" do
    tag = view.audioproxy_preload_link_tag(SOURCE, html: { fetchpriority: "high" })

    assert_includes tag, %(fetchpriority="high")
    assert_includes tag, %(href="#{Audioproxy.url_for(SOURCE)}")
  end

  test "proxy options never appear as link attributes" do
    tag = view.audioproxy_preload_link_tag(SOURCE, raw: "f:opus")

    refute_includes tag, "raw="
  end

  test "an unknown proxy option raises instead of becoming a link attribute" do
    error = assert_raises(ArgumentError) { view.audioproxy_preload_link_tag(SOURCE, bitrat: 96) }

    assert_match(/unknown Audioproxy option/, error.message)
  end

  test "preload html: must be a Hash" do
    error = assert_raises(ArgumentError) { view.audioproxy_preload_link_tag(SOURCE, html: "audio") }

    assert_match(/html: must be a Hash/, error.message)
  end

  test "an attachment reaches the preload helper as its resolved source" do
    recording = attached_recording

    assert_includes view.audioproxy_preload_link_tag(recording.audio, format: "opus"),
      %(href="#{Audioproxy.url_for("local://#{disk_path_for(recording)}", format: "opus")}")
  end

  test "a blob reaches the preload helper as its resolved source" do
    recording = attached_recording

    assert_includes view.audioproxy_preload_link_tag(recording.audio.blob, format: "opus"),
      %(href="#{Audioproxy.url_for("local://#{disk_path_for(recording)}", format: "opus")}")
  end

  # The hint and the element must name one variant. A differing byte is a
  # different cache key and a preload the browser never matches to the tag.
  #
  # Both helpers run their URL through path_to_asset, so comparing them only to
  # each other would pass just as happily if that rewrote the URL — identically,
  # for both. Audioproxy.url_for is the third point that makes it non-circular.
  test "the preload href is byte-identical to the audio tag's src" do
    options = { format: "opus", bitrate: 96 }
    href = view.audioproxy_preload_link_tag(SOURCE, **options)[/href="([^"]+)"/, 1]
    src = view.audioproxy_audio_tag(SOURCE, **options)[/src="([^"]+)"/, 1]

    assert_equal src, href
    assert_equal Audioproxy.url_for(SOURCE, **options), href
  end

  # path_to_asset is asset-pipeline machinery. It should hand an absolute URL
  # back untouched, but a rewritten path is a bad signature, so both tag helpers
  # are asserted against audioproxy_url rather than only against each other.
  test "an endpoint path prefix survives both tag helpers" do
    previous = Audioproxy.config.endpoint
    Audioproxy.config.endpoint = "https://cdn.example.com/audio"

    assert_equal Audioproxy.url_for(SOURCE, format: "opus"),
      view.audioproxy_preload_link_tag(SOURCE, format: "opus")[/href="([^"]+)"/, 1]
    assert_equal Audioproxy.url_for(SOURCE, format: "opus"),
      view.audioproxy_audio_tag(SOURCE, format: "opus")[/src="([^"]+)"/, 1]
  ensure
    Audioproxy.config.endpoint = previous
  end

  private
    # Asked of the real DiskService, not restated from the layout rule. Written
    # out longhand here once, this said "#{key[0..1]}/#{key[2..3]}/#{key}" — the
    # implementation's own rule, which made the assertion agree with the code by
    # construction and would have passed just as happily while the layout was
    # wrong.
    def disk_path_for(recording)
      service = ActiveStorage::Blob.service
      root = Pathname.new(File.expand_path(service.root))

      Pathname.new(service.path_for(recording.audio.key)).relative_path_from(root).to_s
    end
end
