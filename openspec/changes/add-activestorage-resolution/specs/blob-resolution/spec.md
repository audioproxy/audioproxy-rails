## ADDED Requirements

### Requirement: Blob and attachment inputs resolve to source strings
`Audioproxy.url_for` (and the view helpers) SHALL accept an `ActiveStorage::Blob`, an attachment, or an `ActiveStorage::Attached::One`, unwrap it to its blob, and resolve a proxy source string from the blob's service before building the URL. String sources SHALL bypass resolution unchanged.

#### Scenario: Attachment unwraps to its blob
- **WHEN** `url_for(user.audio)` is called where `user.audio` is an attached file on a supported service
- **THEN** the URL is identical to calling `url_for` with the blob's resolved source string

#### Scenario: Unattached attachment raises
- **WHEN** `url_for(user.audio)` is called and nothing is attached
- **THEN** an error is raised naming the attachment, distinct from the unsupported-service error

### Requirement: S3 service resolution
A blob on an S3 service SHALL resolve to `s3://{bucket}/{key}`, with the bucket read from the service's configuration and the blob key used verbatim.

#### Scenario: S3 blob
- **WHEN** a blob with key `abc123` lives on an S3 service whose bucket is `masters`
- **THEN** the resolved source is `s3://masters/abc123`

### Requirement: Disk service resolution follows the path_for layout
A blob on a Disk service SHALL resolve to `local://{key[0..1]}/{key[2..3]}/{key}` — the service's two hashed subdirectories — so the proxy finds the file when its `AP_LOCAL_ROOT` equals the Disk service root. The layout knowledge SHALL live in a single module, contract-tested against ActiveStorage's own `DiskService` path computation.

#### Scenario: Disk blob
- **WHEN** a blob with key `wxyz9876` lives on a Disk service
- **THEN** the resolved source is `local://wx/yz/wxyz9876`

#### Scenario: Layout matches DiskService
- **WHEN** the resolver's path for a key is compared with `DiskService#path_for` for the same key under the same root
- **THEN** the relative paths are identical

### Requirement: Unsupported services fail with an actionable error
A blob on any other service (GCS, Azure, Mirror, …) SHALL raise `Audioproxy::UnsupportedServiceError` naming the service class, stating the supported services, and pointing at the documented alternative: ActiveStorage `rails_storage_proxy` mode behind the proxy's `https` source backend (upstream, on demand).

#### Scenario: GCS blob
- **WHEN** `url_for` is called with a blob on a GCS service
- **THEN** `Audioproxy::UnsupportedServiceError` is raised, its message naming the GCS service class and the `rails_storage_proxy` alternative

#### Scenario: Mirror service is not unwrapped
- **WHEN** `url_for` is called with a blob on a Mirror service whose primary is S3
- **THEN** `Audioproxy::UnsupportedServiceError` is raised naming the mirror class
