## 1. Core resolver hook

- [ ] 1.1 Add a resolver registration hook to the core: `url_for` passes non-String sources to the registered resolver, raises `ArgumentError` when none is registered; core references no ActiveStorage constants
- [ ] 1.2 Tests: standalone behavior unchanged for Strings; non-String without resolver raises; a stub resolver is consulted

## 2. Blob resolver

- [ ] 2.1 Implement blob/attachment/`Attached::One` unwrapping; unattached raises an error naming the attachment
- [ ] 2.2 Implement S3 resolution (`s3://{bucket}/{key}`, bucket from the service instance)
- [ ] 2.3 Implement Disk resolution in an isolated layout module (`local://{key[0..1]}/{key[2..3]}/{key}`)
- [ ] 2.4 Implement `Audioproxy::UnsupportedServiceError` naming the service class and the `rails_storage_proxy` + https-source-backend alternative; Mirror services hit this error un-unwrapped
- [ ] 2.5 Register the resolver from the Railtie when ActiveStorage is present

## 3. Tests and docs

- [ ] 3.1 Service-double tests: S3 resolution, Disk resolution, unsupported service error (GCS double), mirror error, attachment unwrapping, unattached error
- [ ] 3.2 Contract test: layout module output equals `ActiveStorage::Service::DiskService` path computation for the same keys
- [ ] 3.3 End-to-end: blob through `url_for` and `audioproxy_audio_tag` to a signed URL
- [ ] 3.4 README: resolution ladder table, `AP_LOCAL_ROOT` deployment coupling note, and the documented https/`rails_storage_proxy` third rung as the trigger for the upstream proxy slice
