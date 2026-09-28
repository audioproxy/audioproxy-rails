## ADDED Requirements

### Requirement: Info URL shape
`Audioproxy.info_url(source)` SHALL return `{endpoint}/{signature}/info/{source-segment}` — the
proxy's probe-metadata endpoint — with no options segment between the signature and the source. The
signature SHALL cover `/info/{source-segment}` exactly, and the source SHALL be emitted in the same
`enc/` form `url_for` uses.

#### Scenario: Info URL has no options segment
- **WHEN** `Audioproxy.info_url("local://previews/track.wav")` is called with endpoint `https://audio.example.com` and valid key/salt
- **THEN** the result is `https://audio.example.com/{sig}/info/enc/{base64url("local://previews/track.wav")}` with no option segments present

#### Scenario: Info signature matches the published vector
- **WHEN** the path `/info/plain/s3://b/k.wav` is signed with the known-answer key and salt
- **THEN** the signature is `U6nyFdkSvjNo2mlBbJMGk1nwISbdcnEGlgKSWKBfKT4`, proving the builder signs the info shape the way the proxy verifies it

#### Scenario: Blob sources resolve for info URLs
- **WHEN** `Audioproxy.info_url(recording.audio)` is called with the ActiveStorage resolver registered
- **THEN** the attachment resolves to its source string through the same resolver `url_for` uses, and the info URL is built from it

### Requirement: Info URLs accept no proxy options
`info_url` SHALL raise an `ArgumentError` when given `raw:` or any typed option key, naming the
endpoint's no-options rule. The proxy answers `422` to any option segment alongside `info`, so a
rendered option here is a request that cannot succeed.

#### Scenario: Typed option rejected
- **WHEN** `Audioproxy.info_url(source, format: :opus)` is called
- **THEN** an `ArgumentError` is raised and no URL is returned

#### Scenario: Raw option rejected
- **WHEN** `Audioproxy.info_url(source, raw: "f:opus")` is called
- **THEN** an `ArgumentError` is raised

### Requirement: Configured defaults do not reach info URLs
`info_url` SHALL ignore `config.default_options` entirely. This is deliberate asymmetry with every
other entry point: honouring defaults would render an options segment and make every info request a
`422`.

#### Scenario: Defaults are not rendered
- **WHEN** `default_options` is `{ f: :opus, br: 96 }` and `Audioproxy.info_url(source)` is called
- **THEN** the path is `/{sig}/info/{source-segment}` with no `f:opus` and no `br:96` segment

#### Scenario: A raw default is not rendered either
- **WHEN** `default_options` is `{ raw: "f:opus/br:96" }` and `Audioproxy.info_url(source)` is called
- **THEN** the path contains no options segment

### Requirement: Info URLs carry no expiry
`info_url` SHALL ignore `config.expires_in`, and SHALL raise an `ArgumentError` for a per-call
`expires_in:` or `expires_at:` with a non-nil value. The proxy's `/info` grammar has no options
segment and therefore cannot carry `exp`. An explicit `nil` for either SHALL be accepted, since it
asks for the no-expiry URL that `info_url` builds anyway.

#### Scenario: Global expiry is not applied
- **WHEN** `config.expires_in` is one hour and `Audioproxy.info_url(source)` is called
- **THEN** the path is `/{sig}/info/{source-segment}` with no `exp:` segment

#### Scenario: Per-call expiry rejected
- **WHEN** `Audioproxy.info_url(source, expires_in: 1.hour)` is called
- **THEN** an `ArgumentError` is raised naming that info URLs cannot carry an expiry

#### Scenario: Explicit nil expiry accepted
- **WHEN** `Audioproxy.info_url(source, expires_in: nil)` is called
- **THEN** it returns the same URL as `Audioproxy.info_url(source)`

### Requirement: Info URLs honour builder overrides
`info_url` SHALL accept `endpoint:` and `unsigned:` with the same meaning they carry on `url_for`,
since both are builder concerns rather than proxy options.

#### Scenario: Per-call endpoint
- **WHEN** `Audioproxy.info_url(source, endpoint: "https://audio-eu.example.com")` is called
- **THEN** the returned URL is rooted at that endpoint and the global config is unchanged

#### Scenario: Unsigned info URL
- **WHEN** `Audioproxy.info_url(source, unsigned: true)` is called
- **THEN** the signature segment is the literal `insecure` and no key or salt is required

### Requirement: Peaks URL fixes the peaks format
`Audioproxy.peaks_url(source, **options)` SHALL build a variant URL with the format fixed to
`f:peaks`. Peaks are a format rather than a separate endpoint, so the result SHALL be an ordinary
`{endpoint}/{signature}/{options}/{source-segment}` URL whose options segment carries `f:peaks`.

#### Scenario: Minimal peaks URL
- **WHEN** `Audioproxy.peaks_url("local://a.wav")` is called
- **THEN** the options segment is `f:peaks`

#### Scenario: Peaks options render
- **WHEN** `Audioproxy.peaks_url("local://a.wav", pts: 800, pk_fmt: :dat)` is called
- **THEN** the options segment contains `f:peaks`, `pts:800` and `pk_fmt:dat`

#### Scenario: Redundant explicit peaks format accepted
- **WHEN** `Audioproxy.peaks_url(source, format: :peaks)` is called
- **THEN** the URL is identical to calling `peaks_url(source)` with no format

#### Scenario: The peaks format always renders first
- **WHEN** `Audioproxy.peaks_url(source, pts: 800, format: :peaks)` is called
- **THEN** the options segment is `f:peaks/pts:800`, identical to `peaks_url(source, pts: 800)`

#### Scenario: Conflicting explicit format rejected
- **WHEN** `Audioproxy.peaks_url(source, format: :opus)` is called
- **THEN** an `ArgumentError` is raised naming both `peaks` and the requested format

#### Scenario: Raw options rejected
- **WHEN** `Audioproxy.peaks_url(source, raw: "pts:800")` is called
- **THEN** an `ArgumentError` is raised, since a pre-rendered string cannot be screened against the peaks options

#### Scenario: Expiry applies to peaks URLs
- **WHEN** `Audioproxy.peaks_url(source, expires_in: 1.hour)` is called
- **THEN** the options segment is `f:peaks/exp:{timestamp}`, exactly as `url_for` would append it

### Requirement: Peaks URLs accept only options the peaks renderer reads
`peaks_url` SHALL accept `pts`, `pk_fmt`, `pk_bits`, `ch`, `t`, `fade`, `gain`, `norm`, `dl` and
`cb` (in either spelling) and SHALL raise an `ArgumentError` naming the accepted set for any other
option key. An option the peaks renderer ignores still enters the proxy's cache key, so accepting one
would buy a second cache entry, a second stored object and a second render for byte-identical peaks.

#### Scenario: Encoding option rejected
- **WHEN** `Audioproxy.peaks_url(source, bitrate: 96)` is called
- **THEN** an `ArgumentError` is raised naming the options peaks accept

#### Scenario: Time-domain options accepted
- **WHEN** `Audioproxy.peaks_url(source, trim: [12.5, 30], channels: 2)` is called
- **THEN** the options segment contains `t:12.5:30` and `ch:2`

#### Scenario: Peaks bit depth accepted
- **WHEN** `Audioproxy.peaks_url(source, pk_bits: 8)` is called
- **THEN** the options segment is `f:peaks/pk_bits:8`

### Requirement: Peaks URLs apply only the defaults that mean the same thing for peaks
`peaks_url` SHALL apply typed `config.default_options` for `t`, `fade`, `gain`, `norm` and `cb`,
merged under per-call keys as `url_for` merges them, and SHALL skip every other default, including a
`raw:` default. Defaults are written once for audio variants: a default such as `br:96` alongside
`f:peaks` is a `422` from the proxy, and a `ch:` or `dl:` default would change what a peaks request
returns without error, so both are skipped as defaults while remaining accepted per call.

#### Scenario: Audio-only defaults are skipped
- **WHEN** `default_options` is `{ f: :opus, br: 96 }` and `Audioproxy.peaks_url(source)` is called
- **THEN** the options segment is `f:peaks`, with no `f:opus` and no `br:96`

#### Scenario: Allowlisted defaults apply
- **WHEN** `default_options` is `{ f: :opus, norm: :ebu }` and `Audioproxy.peaks_url(source, pts: 800)` is called
- **THEN** the options segment is `f:peaks/norm:ebu/pts:800`, so the waveform follows the normalized audio

#### Scenario: Channel and filename defaults are skipped
- **WHEN** `default_options` is `{ f: :opus, ch: 2, dl: "piece.opus" }` and `Audioproxy.peaks_url(source)` is called
- **THEN** the options segment is `f:peaks`, and `peaks_url(source, ch: 2)` still renders `f:peaks/ch:2`

#### Scenario: A raw default is skipped
- **WHEN** `default_options` is `{ raw: "f:opus/br:96" }` and `Audioproxy.peaks_url(source)` is called
- **THEN** the options segment is `f:peaks`

### Requirement: Peaks URLs do not materialize the channel default
`peaks_url` SHALL NOT emit `ch:1` when no channel count is given, even though the peaks renderer
defaults to it. The gem renders what it was given; the proxy materializes its own defaults into the
cache key.

#### Scenario: Channel default left off
- **WHEN** `Audioproxy.peaks_url(source, pts: 400)` is called with no channel count
- **THEN** the options segment contains no `ch:` part
