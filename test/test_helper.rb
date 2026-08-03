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

# Attaching writes real files under the dummy app's tmp/storage, and the
# transaction each test runs in rolls back the blob *rows* without touching
# them — so without a sweep the directory grows by a few files on every run,
# forever. Include this in any case that attaches.
#
# The sweep deletes the service root rather than purging the blobs, because
# purging cannot work here: the fixture rollback is registered before this
# teardown and therefore runs first, leaving `ActiveStorage::Blob.all` empty by
# the time a purge would see it. Emptying the directory needs no rows. It is
# safe because the test service root is a throwaway under the dummy app's tmp/.
module AttachedRecordings
  extend ActiveSupport::Concern

  included do
    teardown do
      service = ActiveStorage::Blob.service
      FileUtils.rm_rf(service.root) if service.respond_to?(:root)
    end
  end

  def attached_recording(title: "Take 1")
    recording = Recording.create!(title: title)
    recording.audio.attach(
      io: StringIO.new("RIFF....WAVE"),
      filename: "take.wav",
      content_type: "audio/wav"
    )
    recording
  end
end

# Load fixtures from the engine
if ActiveSupport::TestCase.respond_to?(:fixture_paths=)
  ActiveSupport::TestCase.fixture_paths = [ File.expand_path("fixtures", __dir__) ]
  ActionDispatch::IntegrationTest.fixture_paths = ActiveSupport::TestCase.fixture_paths
  ActiveSupport::TestCase.file_fixture_path = File.expand_path("fixtures", __dir__) + "/files"
  ActiveSupport::TestCase.fixtures :all
end
