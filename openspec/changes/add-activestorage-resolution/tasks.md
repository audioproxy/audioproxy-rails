## 1. Core resolver hook

- [x] 1.1 Add a resolver registration hook to the core: `url_for` passes non-String sources to the registered resolver, raises `ArgumentError` when none is registered; core references no ActiveStorage constants
- [x] 1.2 Tests: standalone behavior unchanged for Strings; non-String without resolver raises; a stub resolver is consulted

## 2. Blob resolver

- [x] 2.1 Implement blob/attachment/`Attached::One` unwrapping; unattached raises an error naming the attachment
- [x] 2.2 Implement S3 resolution (`s3://{bucket}/{key}`, bucket from the service instance)
- [x] 2.3 Implement Disk resolution in an isolated layout module (`local://{key[0..1]}/{key[2..3]}/{key}`)
- [x] 2.4 Implement `Audioproxy::UnsupportedServiceError` naming the service class and the `rails_storage_proxy` + https-source-backend alternative; Mirror services hit this error un-unwrapped
- [x] 2.5 Register the resolver from the Railtie when ActiveStorage is present

## 3. Tests and docs

- [x] 3.1 Service-double tests: S3 resolution, Disk resolution, unsupported service error (GCS double), mirror error, attachment unwrapping, unattached error
- [x] 3.2 Contract test: layout module output equals `ActiveStorage::Service::DiskService` path computation for the same keys
- [x] 3.3 End-to-end: blob through `url_for` and `audioproxy_audio_tag` to a signed URL
- [x] 3.4 README: resolution ladder table, `AP_LOCAL_ROOT` deployment coupling note, and the documented https/`rails_storage_proxy` third rung as the trigger for the upstream proxy slice
