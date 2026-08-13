# url-building Specification

## Purpose
TBD - created by archiving change add-gem-core-signing. Update Purpose after archive.
## Requirements
### Requirement: URL shape
`Audioproxy.url_for(source, **opts)` SHALL return `{endpoint}/{signature}/{options}/{source-segment}` where the signature covers everything after itself (leading `/` included).

#### Scenario: Full URL round-trip shape
- **WHEN** `Audioproxy.url_for("local://previews/track.wav", raw: "f:opus/br:96")` is called with endpoint `https://audio.example.com` and valid key/salt
- **THEN** the result is `https://audio.example.com/{sig}/f:opus/br:96/enc/{base64url("local://previews/track.wav")}` where `{sig}` verifies against the proxy's signer for that path

### Requirement: Source is emitted in enc form
The builder SHALL encode the source string as `enc/` + unpadded base64url. The builder SHALL NOT emit `plain/` sources.

#### Scenario: Source encoding
- **WHEN** the source is `s3://masters/a track.wav` (contains a space)
- **THEN** the source segment is `enc/` followed by the unpadded base64url of the exact source string, with no percent-escaping applied

### Requirement: Source must be a non-empty string
The builder SHALL raise an `ArgumentError` when the source is `nil`, empty, or not a String, rather than signing a URL with an empty or stringified `enc/` payload.

#### Scenario: Nil source rejected
- **WHEN** `Audioproxy.url_for(nil)` is called
- **THEN** an `ArgumentError` is raised, and no URL is returned

#### Scenario: Non-String source rejected
- **WHEN** `Audioproxy.url_for(123)` is called
- **THEN** an `ArgumentError` is raised naming the offending class

### Requirement: Raw options passthrough
`url_for` SHALL accept `raw:` — a pre-rendered options string used verbatim as the options segment. `raw:` SHALL NOT be combined with typed option keys in the same call; doing so raises an `ArgumentError` (ambiguous intent). When no options are supplied (no `raw:`, no typed keys, no default options), the options segment SHALL be `f:mp3` (the proxy's default format made explicit), because the proxy's path grammar has no optionless form. Configured `default_options` merge under per-call typed keys key-by-key (per-call wins); a per-call `raw:` replaces defaults entirely.

#### Scenario: Raw string used verbatim
- **WHEN** `raw: "f:opus/t:12.5:30"` is passed
- **THEN** the options segment is exactly `f:opus/t:12.5:30`

#### Scenario: No options at all
- **WHEN** `url_for` is called with no options and no configured defaults
- **THEN** the options segment is `f:mp3`

#### Scenario: Raw mixed with typed keys raises
- **WHEN** `url_for(source, raw: "f:opus", br: 96)` is called
- **THEN** an `ArgumentError` is raised

#### Scenario: Typed keys merge over defaults
- **WHEN** `default_options` is `{ f: :opus, br: 96 }` and `url_for(source, br: 128)` is called
- **THEN** the options segment contains `f:opus` and `br:128`

#### Scenario: Per-call typed keys replace a raw default
- **WHEN** `default_options` is `{ raw: "f:opus/br:96" }` and `url_for(source, f: :mp3)` is called
- **THEN** the options segment is `f:mp3`

#### Scenario: Defaults mixing raw with typed keys are rejected at configuration time
- **WHEN** `default_options` is assigned `{ raw: "f:opus", br: 96 }`
- **THEN** an `ArgumentError` is raised at assignment

### Requirement: Per-call endpoint override
`url_for` SHALL accept `endpoint:` overriding the configured endpoint for that call only.

#### Scenario: Second proxy instance
- **WHEN** `Audioproxy.url_for("local://a.wav", endpoint: "https://audio-eu.example.com")` is called with a different global endpoint configured
- **THEN** the returned URL is rooted at `https://audio-eu.example.com` and the global config is unchanged

### Requirement: Endpoint path prefixes do not disturb signing
An endpoint carrying a path prefix SHALL produce the same signature segment as a prefixless endpoint for the same source and options, because the HMAC covers only the path after the signature segment.

#### Scenario: Prefixed and bare endpoints sign identically
- **WHEN** the same source and options are built against `https://audio.example.com` and `https://cdn.example.com/audio`
- **THEN** both URLs contain byte-identical signature, options, and source segments, and the second is rooted at `https://cdn.example.com/audio/`

#### Scenario: Trailing slash normalization
- **WHEN** the endpoint is configured as `https://audio.example.com/`
- **THEN** the generated URL contains no double slash after the host

### Requirement: Module-level entry point is Rails-free
`Audioproxy.url_for` SHALL be usable with only the gem's own files loaded (no Rails, no ActiveSupport), so it works in jobs, mailers, and serializers of any Ruby program. Non-String sources SHALL be resolved through a resolver registration hook: the Rails layer registers the ActiveStorage blob resolver when ActiveStorage is present, and the core itself SHALL reference no ActiveStorage constants. With no resolver registered, a non-String source raises an `ArgumentError`.

#### Scenario: Standalone require
- **WHEN** a plain Ruby script requires `audioproxy` and configures endpoint/key/salt
- **THEN** `Audioproxy.url_for` returns a correct URL with no Rails constants defined

#### Scenario: Non-String source without a resolver
- **WHEN** `Audioproxy.url_for(Object.new)` is called outside Rails
- **THEN** an `ArgumentError` is raised

#### Scenario: Registered resolver handles blobs
- **WHEN** the Rails layer has registered the blob resolver and `url_for` receives a blob
- **THEN** the blob is resolved to a source string and the URL is built from it

### Requirement: Expiry keywords on url_for
`url_for` SHALL accept `expires_in:` (ActiveSupport duration or positive Integer seconds, added to the current time at build time) and `expires_at:` (Time-like or Integer unix timestamp, used as-is), mutually exclusive, rendering an `exp:<unix-seconds>` option segment; validation SHALL raise at call time for both keywords together, a non-positive `expires_in`, an `expires_at` at or before the current time, or an uncoercible type.

#### Scenario: Duration arithmetic at build time
- **WHEN** `url_for(source, expires_in: 1.hour)` is called with the clock frozen
- **THEN** the options segment contains `exp:` with exactly the frozen time plus 3600 seconds

#### Scenario: Both keywords raise
- **WHEN** `expires_in:` and `expires_at:` are both given
- **THEN** an ArgumentError is raised at the call site, and no URL is produced

#### Scenario: Past expires_at raises
- **WHEN** `expires_at:` is at or before the current time
- **THEN** an error is raised rather than minting an already-dead URL

