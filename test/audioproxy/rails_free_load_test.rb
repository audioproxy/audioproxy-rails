require "test_helper"

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
