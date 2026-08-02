## ADDED Requirements

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

### Requirement: Raw options passthrough
`url_for` SHALL accept `raw:` — a pre-rendered options string used verbatim as the options segment. When no options are supplied (no `raw:`, no default options), the options segment SHALL be `f:mp3` (the proxy's default format made explicit), because the proxy's path grammar has no optionless form.

#### Scenario: Raw string used verbatim
- **WHEN** `raw: "f:opus/t:12.5:30"` is passed
- **THEN** the options segment is exactly `f:opus/t:12.5:30`

#### Scenario: No options at all
- **WHEN** `url_for` is called with no options and no configured defaults
- **THEN** the options segment is `f:mp3`

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
`Audioproxy.url_for` SHALL be usable with only the gem's own files loaded (no Rails, no ActiveSupport), so it works in jobs, mailers, and serializers of any Ruby program.

#### Scenario: Standalone require
- **WHEN** a plain Ruby script requires `audioproxy` and configures endpoint/key/salt
- **THEN** `Audioproxy.url_for` returns a correct URL with no Rails constants defined
