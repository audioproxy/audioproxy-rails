require "test_helper"
require_relative "../../fixtures/signature_vectors"

class Audioproxy::Rails::RailtieTest < ActiveSupport::TestCase
  Railtie = Audioproxy::Rails::Railtie

  ENDPOINT = "https://audio.example.com".freeze
  OTHER_KEY_HEX = ("11" * 32).freeze

  setup do
    @config = Audioproxy::Config.new
  end

  def apply(credentials: nil, env: {})
    Railtie.apply_configuration(@config, credentials: credentials, env: env)
  end

  # --- the real boot -------------------------------------------------------
  #
  # test_helper spreads the dummy app's configuration across credentials, ENV
  # and an app initializer, so these assertions pin the precedence chain
  # against an actual Rails boot rather than a hand-called method.

  test "the dummy app boots with the gem's railtie registered" do
    assert ::Rails.application.initialized?
    assert_includes ::Rails.application.railties.map(&:class), Railtie
  end

  test "at boot, ENV fills the gap credentials leave" do
    assert_equal "https://env.example.com", Audioproxy.config.endpoint
  end

  test "at boot, credentials beat ENV" do
    assert_equal SignatureVectors::KEY_HEX.downcase,
      Audioproxy.config.key.unpack1("H*")
    assert_equal SignatureVectors::SALT_HEX.downcase,
      Audioproxy.config.salt.unpack1("H*")
  end

  test "at boot, an app initializer beats both" do
    assert_equal false, Audioproxy.config.unsigned
  end

  # --- credentials ---------------------------------------------------------

  test "credentials configure every attribute" do
    apply(credentials: {
      endpoint: ENDPOINT,
      key: SignatureVectors::KEY_HEX,
      salt: SignatureVectors::SALT_HEX,
      unsigned: true
    })

    assert_equal ENDPOINT, @config.endpoint
    assert_equal SignatureVectors::KEY_HEX.downcase, @config.key.unpack1("H*")
    assert_equal SignatureVectors::SALT_HEX.downcase, @config.salt.unpack1("H*")
    assert_equal true, @config.unsigned
  end

  test "string credential keys work the same as symbols" do
    apply(credentials: { "endpoint" => ENDPOINT, "key" => SignatureVectors::KEY_HEX })

    assert_equal ENDPOINT, @config.endpoint
    assert_equal SignatureVectors::KEY_HEX.downcase, @config.key.unpack1("H*")
  end

  test "credentials arriving as OrderedOptions work" do
    apply(credentials: ActiveSupport::OrderedOptions.new.merge(endpoint: ENDPOINT))

    assert_equal ENDPOINT, @config.endpoint
  end

  test "one setting given under two spellings raises" do
    error = assert_raises(ArgumentError) do
      apply(credentials: { :endpoint => ENDPOINT, "endpoint" => ENDPOINT })
    end

    assert_match(/endpoint twice/, error.message)
    assert_match(/:endpoint and "endpoint"/, error.message)
  end

  test "credentials that are not a hash raise" do
    error = assert_raises(ArgumentError) { apply(credentials: "https://audio.example.com") }

    assert_match(/must be a Hash/, error.message)
  end

  test "credential keys that are neither String nor Symbol raise" do
    error = assert_raises(ArgumentError) { apply(credentials: { 1 => ENDPOINT }) }

    assert_match(/must be Strings or Symbols/, error.message)
  end

  # --- ENV fallback --------------------------------------------------------

  test "ENV supplies every attribute when credentials are absent" do
    apply(env: {
      "AP_ENDPOINT" => ENDPOINT,
      "AP_KEY" => SignatureVectors::KEY_HEX,
      "AP_SALT" => SignatureVectors::SALT_HEX,
      "AP_ALLOW_INSECURE" => "1"
    })

    assert_equal ENDPOINT, @config.endpoint
    assert_equal SignatureVectors::KEY_HEX.downcase, @config.key.unpack1("H*")
    assert_equal SignatureVectors::SALT_HEX.downcase, @config.salt.unpack1("H*")
    assert_equal true, @config.unsigned
  end

  test "attributes resolve independently" do
    apply(
      credentials: { key: SignatureVectors::KEY_HEX, salt: SignatureVectors::SALT_HEX },
      env: { "AP_ENDPOINT" => ENDPOINT }
    )

    assert_equal ENDPOINT, @config.endpoint
    assert_equal SignatureVectors::KEY_HEX.downcase, @config.key.unpack1("H*")
  end

  test "credentials beat ENV per attribute" do
    apply(
      credentials: { key: SignatureVectors::KEY_HEX },
      env: { "AP_KEY" => OTHER_KEY_HEX, "AP_SALT" => SignatureVectors::SALT_HEX }
    )

    assert_equal SignatureVectors::KEY_HEX.downcase, @config.key.unpack1("H*")
    assert_equal SignatureVectors::SALT_HEX.downcase, @config.salt.unpack1("H*")
  end

  test "a blank environment variable is absent, not an empty value" do
    apply(credentials: { key: SignatureVectors::KEY_HEX }, env: { "AP_ENDPOINT" => "" })

    assert_nil @config.endpoint
  end

  test "a nil credential value falls through to ENV" do
    apply(credentials: { endpoint: nil }, env: { "AP_ENDPOINT" => ENDPOINT })

    assert_equal ENDPOINT, @config.endpoint
  end

  # --- AP_ALLOW_INSECURE ---------------------------------------------------

  Audioproxy::Rails::Railtie::TRUE_VALUES.each do |literal|
    test "AP_ALLOW_INSECURE=#{literal} means unsigned" do
      apply(env: { "AP_ALLOW_INSECURE" => literal })
      assert_equal true, @config.unsigned

      apply(env: { "AP_ALLOW_INSECURE" => literal.upcase })
      assert_equal true, @config.unsigned
    end
  end

  Audioproxy::Rails::Railtie::FALSE_VALUES.each do |literal|
    test "AP_ALLOW_INSECURE=#{literal} means signed" do
      @config.unsigned = true
      apply(env: { "AP_ALLOW_INSECURE" => literal })

      assert_equal false, @config.unsigned
    end
  end

  # ActiveModel's boolean cast would read every one of these as true, which is
  # the direction that silently ships unsigned URLs.
  [ "flase", "yes", "no", "on", "off", "2" ].each do |garbage|
    test "AP_ALLOW_INSECURE=#{garbage} raises rather than guessing" do
      error = assert_raises(ArgumentError) { apply(env: { "AP_ALLOW_INSECURE" => garbage }) }

      assert_match(/unsigned from AP_ALLOW_INSECURE/, error.message)
      assert_match(/#{garbage}/, error.message)
    end
  end

  test "a YAML boolean in credentials is taken as-is" do
    apply(credentials: { unsigned: false }, env: { "AP_ALLOW_INSECURE" => "true" })

    assert_equal false, @config.unsigned
  end

  test "a bad unsigned credential names credentials as the source" do
    error = assert_raises(ArgumentError) { apply(credentials: { unsigned: "maybe" }) }

    assert_match(/unsigned from credentials/, error.message)
  end

  # --- absent configuration ------------------------------------------------

  test "nothing configured assigns nothing and does not raise" do
    apply(credentials: nil, env: {})

    assert_nil @config.endpoint
    assert_nil @config.key
    assert_nil @config.salt
    assert_equal false, @config.unsigned
  end

  test "the failure surfaces at url_for, not at boot" do
    apply(credentials: nil, env: {})

    error = assert_raises(Audioproxy::ConfigurationError) do
      Audioproxy::UrlBuilder.new(@config).url_for("local://a.wav")
    end
    assert_match(/no endpoint configured/, error.message)
  end

  test "an endpoint but no signing material still raises at url_for" do
    apply(credentials: { endpoint: ENDPOINT })

    error = assert_raises(Audioproxy::ConfigurationError) do
      Audioproxy::UrlBuilder.new(@config).url_for("local://a.wav")
    end
    assert_match(/key and salt not configured/, error.message)
  end
end
