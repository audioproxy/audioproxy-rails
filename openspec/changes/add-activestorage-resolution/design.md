## Context

The proxy resolves sources by scheme: `local://` paths under its `AP_LOCAL_ROOT`, with `s3://` and `https://` arriving via the proxy's own `add-remote-files-source` work. ActiveStorage identifies files by `blob.key` and hides physical layout inside each service:

- The S3 service stores objects at `{bucket}/{key}`.
- The Disk service stores files at `{root}/{key[0..1]}/{key[2..3]}/{key}` (its `path_for` layout — two hashed subdirectories derived from the key).
- Every other service (GCS, Azure, Mirror) has no proxy-side counterpart today. The general-purpose bridge is ActiveStorage's `rails_storage_proxy` mode (direct 200 responses, no redirect) combined with an `https` source backend on the proxy — parked upstream "on demand".

The resolution ladder (settled): S3 and Disk ship now; the `https` rung is documented as the trigger for the upstream slice.

## Goals / Non-Goals

**Goals:**

- `url_for` accepts blobs, attachments, and `Attached::One`, resolving to `s3://` or `local://` source strings.
- Disk `path_for` knowledge isolated in one module.
- Clear, documented failure for unsupported services.
- Tests against service doubles.

**Non-Goals:**

- The `https`/`rails_storage_proxy` rung (documented, not built — blocked on the proxy's `https` source backend).
- `blob.representation` transparency hook.
- Mirror-service resolution (resolving through to the primary), GCS/Azure support, direct-upload or variant/preview blobs (audio has no ActiveStorage variants).

## Decisions

### D1: Resolution dispatches on the blob's service class, not service name

`blob.service` is inspected by class (`ActiveStorage::Service::S3Service`, `::DiskService`) rather than by the configured service *name* (`:amazon`, `:local` are just labels). Mirror services are not unwrapped (non-goal); they hit the unsupported-service error naming the mirror explicitly. Attachments and `Attached::One` unwrap to their blob first (`#blob`); an unattached `Attached::One` (nil blob) raises `Audioproxy::UnattachedError` naming the attachment, distinct from the unsupported-service error.

The match is on the class *names* in `service.class.ancestors`, not on the constants themselves. Naming `ActiveStorage::Service::S3Service` in the resolver would load that file, and it requires `aws-sdk-s3` — a gem an app on Disk storage has no reason to bundle, and one this gem must not force. (`defined?` is no escape: it answers for an autoload-registered constant without triggering the load, so the guard would pass and the reference behind it would still raise `LoadError`.) Walking ancestor names rather than matching one name also means an app's own subclass of a supported service resolves the way its parent does, at no extra cost. This is a spelling of D1, not a departure from it: the discriminator is still the service class and never the configured label.

### D2: S3 → `s3://{bucket}/{key}`

Bucket comes from the service instance (`service.bucket.name` via the aws-sdk resource the service holds). The blob key is used verbatim — ActiveStorage keys are base36/base58 tokens, safe in a source string, and the `enc/` encoding (core slice) makes escaping a non-issue regardless.

### D3: Disk → `local://{key[0..1]}/{key[2..3]}/{key}`, layout isolated

One module (`BlobResolver::DiskLayout` or similar) owns the two-hashed-subdirectory rule, mirroring `DiskService#path_for`/`folder_for`. If ActiveStorage ever changes the layout, there is exactly one place to touch, and the module's test states the contract against a real `DiskService` instance (cheap: it is filesystem-math only, no files written). The deployment contract — proxy `AP_LOCAL_ROOT` must equal the Disk service root — is README material; the gem cannot verify it and does not try.

### D4: Unsupported services raise `Audioproxy::UnsupportedServiceError`

The error names the blob's service class and states the two supported services, and points at the documented third rung: run ActiveStorage in `rails_storage_proxy` mode behind the proxy's `https` source backend once that backend exists upstream. Rationale: this error message is the demand-signal channel — the user who hits it is the person the upstream slice is waiting for.

### D5: String sources bypass resolution entirely

`url_for` with a String behaves exactly as before; resolution engages only for ActiveStorage objects, and only when ActiveStorage is loaded (`defined?` guard). The core gem stays Rails-free: the resolver lives in the Rails layer and `url_for` consults it through a small registration hook rather than referencing ActiveStorage constants in the core.

## Risks / Trade-offs

- [Disk `path_for` is private-ish API that could change between Rails versions] → Isolated in one module; contract-tested against the real `DiskService` computation, so a Rails upgrade that changes the layout fails the suite immediately and loudly.
- [`AP_LOCAL_ROOT` misalignment produces proxy-side 404s that look like gem bugs] → README deployment note plus the resolver docstring; nothing else the client can do — the coupling is unavoidable by design (disk URLs redirect; the proxy refuses redirects).
- [S3 bucket extraction depends on aws-sdk internals held by the service] → It is the service's documented public surface (`service.bucket`); doubles in tests keep the suite free of aws-sdk, with the accessor chain pinned in one place.
- [Mirror services silently hold a supported primary] → Explicitly not unwrapped; the error names the mirror class so the operator can point config at the primary service instead. Revisit on demand.
