require "test_helper"
require_relative "../fixtures/signature_vectors"

# Guards the extraction seam: the core must load in a plain Ruby process with
# Rails absent. Runs in a subprocess with Bundler's environment stripped so
# nothing pulls Rails in behind our back.
class Audioproxy::RailsFreeLoadTest < ActiveSupport::TestCase
  GEM_ROOT = File.expand_path("../..", __dir__)

  test "requiring the core defines Audioproxy but not Rails" do
    script = <<~RUBY
      require "audioproxy"
      abort "Audioproxy undefined" unless defined?(Audioproxy)
      abort "Rails leaked into the core" if defined?(Rails)
      abort "Audioproxy::VERSION undefined" unless defined?(Audioproxy::VERSION)
    RUBY

    output, status = rails_free_ruby(script)

    assert status.success?, "expected a Rails-free load to succeed, got: #{output}"
  end

  test "a standalone script generates a URL the proxy's signer would verify" do
    script = <<~RUBY
      require "audioproxy"
      abort "Rails leaked into the core" if defined?(Rails)

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
