# url-building Specification

## Purpose
How the gem assembles the proxy's three signed URL shapes from a source and a description of what
to fetch: a rendered variant (`url_for`), probe metadata (`info_url`) and waveform peaks
(`peaks_url`). It covers endpoint joining, the `enc/` source segment, which options, defaults and
expiry each shape may carry, and the rule behind all of it: an input the proxy would refuse raises
at the call site rather than producing a URL that looks valid and fails at request time.
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

#### Scenario: A timestamp past the proxy's bound raises
- **WHEN** `expires_at:` exceeds the proxy's maximum (`253_402_300_799`), as a millisecond timestamp does
- **THEN** an error is raised, rather than emitting a URL the proxy answers with a 422

### Requirement: exp is reachable only through the expiry keywords
`url_for` SHALL refuse `exp:` (and its `expires_at` alias) as an ordinary typed option key, and configuration SHALL refuse it in `default_options`, directing the caller to `expires_in:`/`expires_at:` and `config.expires_in` instead. An expiry written as a plain option bypasses the validation above, and the two mistakes it invites — a timestamp already past, and a millisecond timestamp — each render a URL that looks correct and is refused at request time.

#### Scenario: exp as an option key raises
- **WHEN** `url_for(source, exp: 1767229200)` is called
- **THEN** an `ArgumentError` is raised naming `expires_in:` and `expires_at:`, and no URL is produced

#### Scenario: exp in default_options raises at assignment
- **WHEN** `config.default_options = { exp: 1767229200 }` is assigned
- **THEN** an `ArgumentError` is raised, because an absolute instant applied process-globally expires every URL the process builds at one second

### Requirement: An expiry composes with raw options
Because `exp` is a request option rather than a variant option, an expiry SHALL be applied alongside a `raw:` options string rather than being refused as a conflict or silently dropped, and SHALL render after the variant options so the variant prefix is byte-identical to the same call without an expiry. A `raw:` string that already carries its own `exp:` segment SHALL raise when an expiry is also in force, whether that expiry came from a keyword or from `config.expires_in`.

#### Scenario: raw and an expiry compose
- **WHEN** `url_for(source, raw: "f:opus/br:96", expires_in: 1.hour)` is called
- **THEN** the options segment is `f:opus/br:96/exp:<unix-seconds>`, and no conflict is raised

#### Scenario: A duplicated exp raises at the call site
- **WHEN** a `raw:` string already containing `exp:` is combined with a configured or per-call expiry
- **THEN** an `ArgumentError` is raised, rather than emitting two `exp:` segments for the proxy to refuse

#### Scenario: A raw exp passes through when no expiry is in force
- **WHEN** a `raw:` string containing `exp:` is given and no expiry applies
- **THEN** it is rendered verbatim, as the escape hatch it is

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

