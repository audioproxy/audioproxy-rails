require "test_helper"
require "tmpdir"
require "audioproxy/rails/blob_resolver"

class Audioproxy::Rails::BlobResolverTest < ActiveSupport::TestCase
  include AttachedRecordings

  # Every supported and unsupported service is stood in for by a double that
  # only reports a class name and a bucket, because that is the whole of what
  # resolution reads. Naming the real constants instead would load
  # ActiveStorage's S3 service file, which requires aws-sdk-s3 — a gem this
  # suite has no reason to carry, and neither does an app on disk storage.
  # The one service that is *not* doubled is Disk: it is the layout this gem
  # reproduces, so it is contract-tested against the real thing below.
  def service_double(class_name, bucket: nil)
    klass = Class.new do
      define_singleton_method(:name) { class_name }
      define_singleton_method(:to_s) { class_name }
      attr_reader :bucket

      def initialize(bucket)
        @bucket = bucket
      end
    end

    klass.new(bucket)
  end

  def bucket_double(name)
    Struct.new(:name).new(name)
  end

  def blob_on(service, key: "wxyz9876abcdefghij0123456789")
    blob = ActiveStorage::Blob.new(key: key, filename: "take.wav", byte_size: 1, checksum: "x")
    blob.define_singleton_method(:service) { service }
    blob
  end

  def resolve(source)
    Audioproxy::Rails::BlobResolver.call(source)
  end

  # --- S3 -------------------------------------------------------------------

  test "a blob on an S3 service resolves to s3://bucket/key" do
    service = service_double("ActiveStorage::Service::S3Service", bucket: bucket_double("masters"))

    assert_equal "s3://masters/abc123", resolve(blob_on(service, key: "abc123"))
  end

  test "the S3 bucket comes from the service, not from the service name" do
    service = service_double("ActiveStorage::Service::S3Service", bucket: bucket_double("other-bucket"))

    assert_includes resolve(blob_on(service, key: "abc123")), "s3://other-bucket/"
  end

  # ConfigurationError rather than UnsupportedServiceError: S3 is supported, so
  # an unset bucket is a misconfiguration, and saying "unsupported" would send
  # the reader to fix the wrong thing.
  test "an S3 service reporting no bucket raises a configuration error, not an unsupported one" do
    service = service_double("ActiveStorage::Service::S3Service", bucket: bucket_double(""))

    error = assert_raises(Audioproxy::ConfigurationError) { resolve(blob_on(service)) }

    assert_match(/bucket/, error.message)
  end

  test "a subclass of a supported service resolves like its parent" do
    parent = Class.new do
      define_singleton_method(:name) { "ActiveStorage::Service::S3Service" }
    end
    subclass = Class.new(parent) do
      define_singleton_method(:name) { "MyApp::TieredS3Service" }
      def bucket = Struct.new(:name).new("masters")
    end

    assert_equal "s3://masters/abc123", resolve(blob_on(subclass.new, key: "abc123"))
  end

  # --- Disk -----------------------------------------------------------------

  test "a blob on a Disk service resolves to local:// with the two hashed folders" do
    blob = ActiveStorage::Blob.new(key: "wxyz9876", filename: "take.wav", byte_size: 1, checksum: "x")
    blob.service_name = "test"

    assert_equal "local://wx/yz/wxyz9876", resolve(blob)
  end

  # The keys that matter here are the awkward ones. An earlier version of this
  # test used only realistic tokens and "abcd"/"abcde" — every key ≥4 characters
  # with no separator — which is exactly the region where a naive
  # "#{folder}/#{key}" agrees with DiskService. It passed while the layout was
  # wrong for "ab", "ab/cd" and "/foo".
  DISK_PARITY_KEYS = [
    ActiveStorage::Blob.generate_unique_secure_token,
    ActiveStorage::Blob.generate_unique_secure_token,
    "wxyz9876",
    "abcde",
    "abcd",
    "abc",
    "ab",
    "a",
    "ab/cd",
    "/foo",
    "a..b",
    "ünïcödé-kéy"
  ].freeze

  # Keys DiskService refuses outright — dot segments and null bytes. It never
  # computes a path for these, so there is no parity to assert: only that this
  # gem refuses them too, rather than emitting a source string DiskService
  # would have called invalid. The last one is written as an escape on purpose;
  # a literal NUL in the source is invisible in every diff and editor.
  DISK_REJECTED_KEYS = [ "..", "../evil", "../../etc/passwd", "a/../b", ".", "a\0b" ].freeze

  test "the disk layout module matches DiskService's own path computation" do
    service = ActiveStorage::Service::DiskService.new(root: Dir.mktmpdir)
    root = Pathname.new(File.expand_path(service.root))

    DISK_PARITY_KEYS.each do |key|
      expected = Pathname.new(service.path_for(key)).relative_path_from(root).to_s

      assert_equal expected, Audioproxy::Rails::BlobResolver::DiskLayout.relative_path_for(key),
        "layout drifted from DiskService for key #{key.inspect}"
    end
  end

  test "every key DiskService rejects is rejected here too" do
    service = ActiveStorage::Service::DiskService.new(root: Dir.mktmpdir)

    DISK_REJECTED_KEYS.each do |key|
      assert_raises(ActiveStorage::InvalidKeyError, "DiskService now accepts #{key.inspect}; this test's premise is stale") do
        service.path_for(key)
      end

      assert_raises(ArgumentError, "#{key.inspect} resolved instead of raising") do
        Audioproxy::Rails::BlobResolver::DiskLayout.relative_path_for(key)
      end
    end
  end

  test "a traversal key raises out of the resolver rather than escaping AP_LOCAL_ROOT" do
    blob = ActiveStorage::Blob.new(key: "../evil.wav", filename: "x.wav", byte_size: 1, checksum: "x")
    blob.service_name = "test"

    error = assert_raises(ArgumentError) { resolve(blob) }

    assert_match(/\.\./, error.message)
  end

  test "a blank blob key raises rather than producing a rootward local:// path" do
    assert_raises(ArgumentError) { Audioproxy::Rails::BlobResolver::DiskLayout.relative_path_for("") }
    assert_raises(ArgumentError) { Audioproxy::Rails::BlobResolver::DiskLayout.relative_path_for(nil) }
  end

  test "no resolved disk path ever begins with a separator" do
    DISK_PARITY_KEYS.each do |key|
      refute_operator Audioproxy::Rails::BlobResolver::DiskLayout.relative_path_for(key), :start_with?, "/"
    end
  end

  # --- unsupported services -------------------------------------------------

  test "a blob on a GCS service raises naming the service and the way forward" do
    service = service_double("ActiveStorage::Service::GCSService")

    error = assert_raises(Audioproxy::UnsupportedServiceError) { resolve(blob_on(service)) }

    assert_match(/GCSService/, error.message)
    assert_match(/rails_storage_proxy/, error.message)
    assert_match(/https/, error.message)
  end

  test "a Mirror service is not unwrapped to its primary but named in the error" do
    service = service_double("ActiveStorage::Service::MirrorService")

    error = assert_raises(Audioproxy::UnsupportedServiceError) { resolve(blob_on(service)) }

    assert_match(/MirrorService/, error.message)
  end

  test "the unsupported-service error names the services that do work" do
    service = service_double("ActiveStorage::Service::AzureStorageService")

    error = assert_raises(Audioproxy::UnsupportedServiceError) { resolve(blob_on(service)) }

    assert_match(/S3/, error.message)
    assert_match(/Disk/, error.message)
  end

  # --- unwrapping -----------------------------------------------------------

  test "an attachment unwraps to its blob" do
    recording = attached_recording

    assert_equal resolve(recording.audio.blob), resolve(recording.audio_attachment)
  end

  test "an Attached::One unwraps to its blob" do
    recording = attached_recording

    assert_equal resolve(recording.audio.blob), resolve(recording.audio)
  end

  test "an unattached Attached::One raises an error naming the attachment" do
    error = assert_raises(Audioproxy::UnattachedError) { resolve(Recording.new.audio) }

    assert_match(/Recording/, error.message)
    assert_match(/audio/, error.message)
  end

  test "the unattached error is distinct from the unsupported-service error" do
    refute_operator Audioproxy::UnattachedError, :<=, Audioproxy::UnsupportedServiceError
    refute_operator Audioproxy::UnsupportedServiceError, :<=, Audioproxy::UnattachedError
  end

  test "anything that is not a blob or an attachment raises ArgumentError" do
    [ Object.new, 123, nil, [] ].each do |source|
      error = assert_raises(ArgumentError) { resolve(source) }

      assert_match(/#{source.class}/, error.message)
    end
  end
end
