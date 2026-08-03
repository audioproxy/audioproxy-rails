# Configure Rails Environment
ENV["RAILS_ENV"] = "test"

# The dummy app's audioproxy configuration is deliberately spread across all
# three sources so that one real boot exercises the whole precedence chain
# (D2). It has to be set before the app boots, because the railtie initializer
# reads ENV once.
#
#   credentials (test/dummy/config/credentials.yml.enc, master key committed
#                beside it — a fixture, nothing secret):  key, salt
#   ENV (here):                          endpoint, a losing key, unsigned
#   app initializer (test/dummy/config/initializers/audioproxy.rb): unsigned
#
# So: endpoint proves ENV fills a credentials gap, key proves credentials beat
# ENV, and unsigned proves an app initializer beats both.
ENV["AP_ENDPOINT"] = "https://env.example.com"
ENV["AP_KEY"] = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
ENV["AP_ALLOW_INSECURE"] = "true"

require_relative "../test/dummy/config/environment"
ActiveRecord::Migrator.migrations_paths = [ File.expand_path("../test/dummy/db/migrate", __dir__) ]
require "rails/test_help"

# Load fixtures from the engine
if ActiveSupport::TestCase.respond_to?(:fixture_paths=)
  ActiveSupport::TestCase.fixture_paths = [ File.expand_path("fixtures", __dir__) ]
  ActionDispatch::IntegrationTest.fixture_paths = ActiveSupport::TestCase.fixture_paths
  ActiveSupport::TestCase.file_fixture_path = File.expand_path("fixtures", __dir__) + "/files"
  ActiveSupport::TestCase.fixtures :all
end
