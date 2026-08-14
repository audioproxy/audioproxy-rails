require "test_helper"
require "support/server_roundtrip"

# The assertions this gem has never made: not that a URL has the right bytes,
# but that a real proxy accepts it. Everything here is tagged `:server` and
# skipped by `bin/test`; see test/support/server_roundtrip.rb.
class Audioproxy::RoundtripTest < ActiveSupport::TestCase
  include Audioproxy::Test::ServerRoundtrip

  test "a signed URL renders" do
    url = url_for

    # The container runs with AP_ALLOW_INSECURE, so an `insecure` URL also
    # answers 200 — which means without this line the assertion below would
    # still pass if url_for stopped signing altogether, and this file's whole
    # reason for existing would be gone with nothing failing. Config#initialize
    # sets unsigned = false and never reads ENV, so this holds today; it is
    # asserted rather than assumed because test_helper.rb sets
    # AP_ALLOW_INSECURE=true process-wide.
    assert_not_includes url, "/#{Audioproxy::UrlBuilder::INSECURE_SEGMENT}/",
      "url_for signed nothing, so the round-trip below proves only that the proxy is permissive"

    response = get(url)

    assert_equal "200", response.code,
      against_proxy("a URL from url_for was refused by the proxy that signed it", response)
    assert_equal "audio/mpeg", response["content-type"],
      against_proxy("the default f:mp3 did not render as mp3")
    assert_predicate response.body.bytesize, :positive?,
      against_proxy("the proxy answered 200 with an empty body")
  end

  # Without this, the test above is equally satisfied by a proxy that accepts
  # everything, and would have proved nothing about the signature.
  #
  # 401, not 403 (D5): AudioProxy.ErrorJSON maps :invalid_signature to the 401
  # row, and §5 of the proxy's API has no 403 at all. Asserted exactly, so that
  # if the proxy ever moves it this suite says which way.
  test "the signature is load-bearing" do
    tampered = url_for(br: 96).sub("/br:96/", "/br:64/")
    response = get(tampered)

    assert_equal "401", response.code,
      against_proxy("a tampered path was not refused", response)
    assert_includes response.body, "invalid_signature",
      against_proxy("the refusal was not a signature refusal", response)
  end

  test "an unsigned URL renders under AP_ALLOW_INSECURE" do
    url = url_for(unsigned: true)

    assert_includes url, "/#{Audioproxy::UrlBuilder::INSECURE_SEGMENT}/",
      "url_for(unsigned: true) did not emit the literal segment the proxy looks for"

    response = get(url)

    assert_equal "200", response.code,
      against_proxy("an unsigned URL was refused by a proxy running with AP_ALLOW_INSECURE", response)
  end

  # Byte-correctness says the option segment reads `f:opus/br:96`. This says the
  # proxy read it the same way and rendered that variant, which no vector can.
  test "a typed-options URL renders the variant it names" do
    response = get(url_for(f: "opus", br: 96))

    assert_equal "200", response.code,
      against_proxy("a typed-options URL was refused", response)
    assert_equal "audio/ogg", response["content-type"],
      against_proxy("f:opus did not render as ogg/opus")
    assert response.body.start_with?("OggS"),
      against_proxy("the body was not an Ogg stream")
  end
end

# The slice add-expiring-urls deferred (its task 3.4). Byte comparison cannot
# reach any of this: `exp:1767229200` is a correct-looking segment whether or
# not the proxy agrees about when it expires, which refusal it is, or where the
# boundary sits.
class Audioproxy::RoundtripExpiryTest < ActiveSupport::TestCase
  include Audioproxy::Test::ServerRoundtrip

  test "an expiring URL renders before its expiry" do
    response = get(url_for(expires_in: 60))

    assert_equal "200", response.code,
      against_proxy("a live expiring URL was refused", response)
    assert_equal "audio/mpeg", response["content-type"],
      against_proxy("an expiring URL rendered differently from one with no expiry")
  end

  # 410, and specifically not 403 (the wrong refusal) or 422 (the proxy failing
  # to parse `exp` at all, which would make every other expiry assertion here
  # vacuous).
  # The window is five seconds rather than one, and the wait is derived from the
  # `exp` the gem actually emitted rather than hard-coded.
  #
  # `expires_in: 1` gives the *first* request a budget of only `2.0 - f` seconds
  # (where f is the sub-second phase at build time), so between one and two —
  # and the request has to complete a cold ffmpeg render inside it. That
  # measured ~0.5s locally, which is under 2x margin on an emulated, loaded CI
  # runner. Exceeding it would fail the liveness assertion below and report a
  # gem defect where the only fact is that the runner was slow.
  test "an expired URL is gone, not forbidden and not unprocessable" do
    url = url_for(expires_in: 5)

    expires_at = url[%r{/exp:(\d+)/}, 1].to_i
    assert_predicate expires_at, :positive?,
      "url_for(expires_in:) emitted no exp: segment, so this test is about nothing"

    assert_equal "200", get(url).code,
      against_proxy("the URL was not live before its expiry, so expiring it proves nothing")

    # The proxy compares whole seconds (`now > exp`, and its now/1 is
    # System.system_time(:second)), so the URL stays live through the whole of
    # the second `exp` names. Waiting past it means reaching exp + 1.
    sleep 0.05 while Time.now.to_i <= expires_at

    response = get(url)

    assert_equal "410", response.code,
      against_proxy("an expired URL was not answered 410", response)
    assert_includes response.body, "expired",
      against_proxy("the 410 was not an expiry refusal", response)
  end

  # add-expiring-urls D5 reads `now > exp` off expiry.ex and concludes the
  # second `exp` names is still served — which is why the gem accepts an
  # expires_at: equal to now + 1 rather than demanding a wider margin. This
  # asks the proxy.
  #
  # The request has to land inside that second, which is a race by construction
  # (D6). It is verified after the fact rather than assumed: a run whose second
  # rolled over mid-request proves nothing, and retries rather than reporting a
  # pass it did not earn.
  test "the boundary is exclusive: the second exp names is still served" do
    attempts = 3

    attempts.times do
      expires_at = Time.now.to_i + 3
      url = url_for(expires_at: Time.at(expires_at))

      sleep 0.02 while Time.now.to_i < expires_at
      response = get(url)

      # Only meaningful if the clock was still inside the expiring second when
      # the proxy answered.
      next unless Time.now.to_i == expires_at

      return assert_equal "200", response.code,
        against_proxy("a URL whose exp names the current second was refused, " \
                      "contradicting the exclusive boundary in add-expiring-urls D5", response)
    end

    skip "could not land a request inside the expiring second in #{attempts} attempts " \
         "(the render outran the clock, not a verdict about #{Audioproxy::Test::ProxyContainer.describe})"
  end
end
