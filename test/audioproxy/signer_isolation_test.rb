require "test_helper"
require_relative "../fixtures/signature_vectors"

# Guards the extraction seam (D1): Audioproxy::Signer must stay liftable into a
# standalone gem, which means it may depend on stdlib and base64 only — not on
# ActiveSupport, not on Rails, and not on any other file in this gem.
#
# Runs in a subprocess with Bundler's environment stripped so nothing pulls
# those in behind our back. The rest of the gem is deliberately not loaded: if
# signer.rb ever grows a reference to Config, UrlBuilder or a core_ext, this
# fails with a NameError or NoMethodError rather than passing quietly.
class Audioproxy::SignerIsolationTest < ActiveSupport::TestCase
  GEM_ROOT = File.expand_path("../..", __dir__)

  test "the signer loads and signs with neither Rails nor ActiveSupport present" do
    vector = SignatureVectors::VECTORS.first

    script = <<~RUBY
      require "audioproxy/signer"

      # Check $LOADED_FEATURES, not defined?(ActiveSupport). A core_ext file
      # such as active_support/core_ext/object/blank.rb patches Object without
      # ever defining the ActiveSupport constant, so a constant check passes
      # while the dependency is very much there.
      leaked = $LOADED_FEATURES.grep(%r{/(active_support|activesupport|rails)/})
      abort "ActiveSupport or Rails leaked into the signer: \#{leaked.first(3).inspect}" unless leaked.empty?

      abort "Rails leaked into the signer" if defined?(Rails)
      abort "the signer pulled in the rest of the gem" if defined?(Audioproxy::UrlBuilder)
      abort "the signer pulled in the rest of the gem" if defined?(Audioproxy::Config)

      signer = Audioproxy::Signer.new(
        key:  [ "#{SignatureVectors::KEY_HEX}" ].pack("H*"),
        salt: [ "#{SignatureVectors::SALT_HEX}" ].pack("H*")
      )

      print signer.sign(#{vector[:rest_of_path].dump})
    RUBY

    signature, status = rails_free_ruby(script)

    assert status.success?, "expected the signer to load in isolation, got: #{signature}"
    assert_equal vector[:signature], signature,
      "the isolated signer must reproduce the proxy's known-answer vector"
  end

  test "requiring the whole gem still defines Audioproxy without Rails" do
    script = <<~RUBY
      require "audioproxy"
      abort "Audioproxy undefined" unless defined?(Audioproxy)
      abort "Rails leaked into the gem" if defined?(Rails)
      abort "Audioproxy::VERSION undefined" unless defined?(Audioproxy::VERSION)
    RUBY

    output, status = rails_free_ruby(script)

    assert status.success?, "expected a Rails-free load to succeed, got: #{output}"
  end

  test "a standalone script generates a URL the proxy's signer would verify" do
    script = <<~RUBY
      require "audioproxy"
      abort "Rails leaked into the gem" if defined?(Rails)

      Audioproxy.configure do |c|
        c.endpoint = "https://audio.example.com"
        c.key  = "#{SignatureVectors::KEY_HEX}"
        c.salt = "#{SignatureVectors::SALT_HEX}"
      end

      print Audioproxy.url_for("s3://masters/2026/piece-final.wav", raw: "f:opus/br:96")
    RUBY

    url, status = rails_free_ruby(script)

    assert status.success?, "expected the standalone script to succeed, got: #{url}"

    source_segment = [ "s3://masters/2026/piece-final.wav" ].pack("m0").tr("+/", "-_").delete("=")
    rest_of_path = "/f:opus/br:96/enc/#{source_segment}"
    key = [ SignatureVectors::KEY_HEX ].pack("H*")
    salt = [ SignatureVectors::SALT_HEX ].pack("H*")
    signature = [ OpenSSL::HMAC.digest("SHA256", key, salt + rest_of_path) ].pack("m0").tr("+/", "-_").delete("=")

    assert_equal "https://audio.example.com/#{signature}#{rest_of_path}", url
  end

  private
    def rails_free_ruby(script)
      env = Bundler.original_env.merge(
        "RUBYOPT" => nil, "RUBYLIB" => nil, "BUNDLE_GEMFILE" => nil
      )

      Bundler.with_unbundled_env do
        output = IO.popen(env, [ RbConfig.ruby, "-I#{File.join(GEM_ROOT, "lib")}", "-e", script ], err: [ :child, :out ], &:read)
        [ output, $? ]
      end
    end
end
