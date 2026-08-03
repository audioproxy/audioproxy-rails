require "test_helper"

# Everything here goes through `view`, a real ActionView::Base, rather than
# through `tests Audioproxy::Rails::Helpers`. Including the module into the test
# case would prove the methods work while saying nothing about whether the
# railtie's on_load(:action_view) hook ever fired.
class Audioproxy::Rails::HelpersTest < ActionView::TestCase
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

  test "html: must be a Hash" do
    error = assert_raises(ArgumentError) { view.audioproxy_audio_tag(SOURCE, html: "controls") }

    assert_match(/html: must be a Hash/, error.message)
  end

  test "audioproxy_audio_tag without html: renders a bare tag" do
    assert_equal %(<audio src="#{Audioproxy.url_for(SOURCE)}"></audio>),
      view.audioproxy_audio_tag(SOURCE)
  end
end
