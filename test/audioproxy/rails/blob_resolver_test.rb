require "test_helper"
require "tmpdir"
require "audioproxy/rails/blob_resolver"

class Audioproxy::Rails::BlobResolverTest < ActiveSupport::TestCase
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

  test "an S3 service reporting no bucket raises rather than emitting s3:///key" do
    service = service_double("ActiveStorage::Service::S3Service", bucket: bucket_double(""))

    assert_raises(Audioproxy::UnsupportedServiceError) { resolve(blob_on(service)) }
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

  test "the disk layout module matches DiskService's own path computation" do
    service = ActiveStorage::Service::DiskService.new(root: Dir.mktmpdir)
    root = Pathname.new(File.expand_path(service.root))

    # Realistic ActiveStorage keys plus the short ones that exercise the
    # slicing, since [0..1]/[2..3] is where a reimplementation drifts.
    keys = [
      ActiveStorage::Blob.generate_unique_secure_token,
      ActiveStorage::Blob.generate_unique_secure_token,
      "wxyz9876",
      "abcde",
      "abcd"
    ]

    keys.each do |key|
      expected = Pathname.new(service.path_for(key)).relative_path_from(root).to_s

      assert_equal expected, Audioproxy::Rails::BlobResolver::DiskLayout.relative_path_for(key),
        "layout drifted from DiskService for key #{key.inspect}"
    end
  end

  test "a blank blob key raises rather than producing a rootward local:// path" do
    assert_raises(ArgumentError) { Audioproxy::Rails::BlobResolver::DiskLayout.relative_path_for("") }
    assert_raises(ArgumentError) { Audioproxy::Rails::BlobResolver::DiskLayout.relative_path_for(nil) }
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

  private
    def attached_recording
      recording = Recording.create!(title: "Take 1")
      recording.audio.attach(
        io: StringIO.new("RIFF....WAVE"),
        filename: "take.wav",
        content_type: "audio/wav"
      )
      recording
    end
end
