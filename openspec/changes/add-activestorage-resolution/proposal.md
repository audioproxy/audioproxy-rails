## Why

Rails apps store audio in ActiveStorage, but the proxy speaks source strings (`s3://…`, `local://…`). Today a caller would have to know each storage service's internal layout to hand-build those strings — including the Disk service's hashed two-level directory scheme, which is effectively private API. This slice teaches the gem to resolve an ActiveStorage blob (or attachment) to the right proxy source string, so `audioproxy_url(user.audio)` just works.

## What Changes

- `Audioproxy.url_for` (and therefore the view helpers) accepts, in addition to a source string: an `ActiveStorage::Blob`, an `ActiveStorage::Attached::One`, and an attachment, resolving each to a source string by the blob's service type:
  - **S3 service** → `s3://{bucket}/{blob.key}` — bucket read from the service's configuration.
  - **Disk service** → `local://{xx}/{yy}/{blob.key}` following the service's `path_for` layout (two hashed subdirectories). Requires the proxy's `AP_LOCAL_ROOT` to point at the same storage root; documented as an unavoidable deployment coupling — normal ActiveStorage disk URLs are redirecting Rails routes, and the proxy's HTTPS backend refuses redirects by design.
  - **Any other service** → a clear, actionable error. The error message documents the future third rung: ActiveStorage `rails_storage_proxy` URLs (direct 200, no redirect) via the proxy's `https` source backend, which is parked upstream ("on demand") — this gem is the first real demand signal for it.
- Disk-layout knowledge isolated in one module so its fiddliness has a single home.
- Resolution tested against service doubles (S3 and Disk layouts), not live services.
- No `blob.representation` hook, no mirror-service handling beyond the primary, no direct-upload awareness.

## Capabilities

### New Capabilities

- `blob-resolution`: ActiveStorage blob/attachment → proxy source string mapping, per service type, including the unsupported-service error contract.

### Modified Capabilities

- `url-building`: `url_for`'s accepted source types widen from String to String-or-ActiveStorage objects.

## Impact

- New code: `lib/audioproxy/rails/blob_resolver.rb` (isolating the Disk `path_for` layout), dispatch in `url_for` when ActiveStorage constants are present.
- Tests: service doubles for S3 and Disk; error path for unsupported services.
- Docs: deployment note on `AP_LOCAL_ROOT` = ActiveStorage disk root; the documented trigger for the upstream `https` source backend slice.
- Depends on: `add-gem-core-signing`, `add-rails-integration` (ActiveStorage implies Rails context).
