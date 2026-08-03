require "audioproxy"

module Audioproxy
  # Raised when a blob lives on a storage service this gem cannot express as a
  # proxy source string. Carries the way forward, because the person reading it
  # is the demand signal for the upstream slice that would fix it (D4).
  class UnsupportedServiceError < StandardError; end

  # Raised when an attachment has no blob behind it. Deliberately its own class:
  # "you attached nothing" and "your storage service is unsupported" are
  # different problems with different fixes.
  class UnattachedError < StandardError; end

  module Rails
    # Turns ActiveStorage objects into the source strings the proxy speaks.
    # Registered with the core by the railtie; the core itself never names an
    # ActiveStorage constant (D5).
    module BlobResolver
      # Dispatch is on the blob's *service class*, never on the configured
      # service name — :amazon and :local are labels an app picks, and an app
      # may well call its S3 service :local (D1).
      #
      # Matched by class name rather than by constant, because naming
      # ActiveStorage::Service::S3Service here would load its file, and that
      # file requires aws-sdk-s3 — a gem an app storing on disk has no reason to
      # bundle. Ancestor names, so an app's own subclass of a supported service
      # resolves the way its parent does.
      #
      # A Mirror service is not in this table and is not unwrapped to its
      # primary (non-goal): it raises, naming the mirror, so the operator makes
      # the choice of which service to point at rather than the gem guessing.
      SERVICES = {
        "ActiveStorage::Service::S3Service" => :s3,
        "ActiveStorage::Service::DiskService" => :disk
      }.freeze

      SUPPORTED = "S3 and Disk".freeze

      class << self
        def call(source)
          blob = unwrap(source)
          service = blob.service

          case kind_of_service(service)
          when :s3   then "s3://#{bucket_for(service)}/#{blob.key}"
          when :disk then "local://#{DiskLayout.relative_path_for(blob.key)}"
          else
            raise UnsupportedServiceError, unsupported_message(service)
          end
        end

        private
          def unwrap(source)
            case source
            when ::ActiveStorage::Blob
              source
            when ::ActiveStorage::Attachment
              source.blob || raise(UnattachedError, "#{describe(source)} has no blob")
            when ::ActiveStorage::Attached::One
              source.blob || raise(UnattachedError, "nothing is attached to #{describe(source)}")
            else
              raise ArgumentError,
                "source must be a String, an ActiveStorage::Blob, or an attachment, got #{source.class}"
            end
          end

          # Both an Attachment and an Attached::One know the record and the
          # attachment name, which is the only part of the error a caller can
          # act on: it says *which* attachment was empty.
          def describe(source)
            "#{source.record.class}##{source.name}"
          rescue NoMethodError
            source.class.name
          end

          def kind_of_service(service)
            service.class.ancestors.each do |ancestor|
              kind = SERVICES[ancestor.name]
              return kind if kind
            end

            nil
          end

          # service.bucket is an Aws::S3::Bucket the service builds from its own
          # configuration; its #name is the bucket string. The one place this
          # accessor chain is spelled out, so an aws-sdk change lands here.
          def bucket_for(service)
            name = String.try_convert(service.bucket.name)

            if name.nil? || name.empty?
              raise UnsupportedServiceError,
                "the S3 service behind this blob reports no bucket name, so #{service.class} " \
                "cannot be resolved to an s3:// source"
            end

            name
          end

          def unsupported_message(service)
            "Audioproxy cannot resolve blobs on #{service.class}; it supports #{SUPPORTED} services. " \
            "Serve this blob through ActiveStorage's rails_storage_proxy mode (which answers 200 " \
            "directly instead of redirecting) behind an https:// source on the proxy — that source " \
            "backend is parked upstream on demand, and this error is the demand."
          end
      end

      # The Disk service hides its layout behind DiskService#path_for: a file
      # for key "wxyz9876" lives at {root}/wx/yz/wxyz9876, under two
      # subdirectories hashed out of the key itself. The proxy is handed the
      # path relative to its own AP_LOCAL_ROOT, so the gem has to reproduce that
      # rule — which makes it the one piece of private-ish Rails API this gem
      # depends on, and the reason it lives alone in a module with a contract
      # test against the real DiskService (D3).
      module DiskLayout
        class << self
          def relative_path_for(key)
            string = String.try_convert(key)

            if string.nil? || string.empty?
              raise ArgumentError, "an ActiveStorage blob key must be a non-empty String, got #{key.inspect}"
            end

            "#{folder_for(string)}/#{string}"
          end

          private
            # Mirrors DiskService#folder_for exactly.
            def folder_for(key)
              [ key[0..1], key[2..3] ].join("/")
            end
        end
      end
    end
  end
end
