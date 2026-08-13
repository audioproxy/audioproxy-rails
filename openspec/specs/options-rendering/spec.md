# options-rendering Specification

## Purpose
TBD - created by archiving change add-options-rendering. Update Purpose after archive.
## Requirements
### Requirement: Typed short-key options
`url_for` SHALL accept the proxy's option keys as keyword arguments — `f:`, `br:`, `q:`, `sr:`, `ch:`, `bd:`, `t:`, `fade:`, `gain:`, `norm:`, `pts:`, `pk_fmt:`, `dl:`, `cb:` — each rendered as a `key:value` segment, joined with `/`, in the order the caller wrote them.

#### Scenario: Basic typed options
- **WHEN** `url_for(source, f: :opus, br: 96)` is called
- **THEN** the options segment is `f:opus/br:96`

#### Scenario: Symbols and strings render alike
- **WHEN** `f: :opus` or `f: "opus"` is passed
- **THEN** both render `f:opus`

#### Scenario: Unknown key raises
- **WHEN** `url_for(source, bt: 96)` is called
- **THEN** an `ArgumentError` is raised listing the recognized keys

### Requirement: Multi-part options as arrays
Options whose grammar takes colon-separated parts (`t`, `fade`, `norm`) SHALL accept arrays, rendered by colon-joining the formatted elements. A scalar value SHALL render as the single-part form.

#### Scenario: Trim with start and duration
- **WHEN** `t: [12.5, 30]` is passed
- **THEN** the segment is `t:12.5:30`

#### Scenario: Trim with start only
- **WHEN** `t: 12.5` is passed
- **THEN** the segment is `t:12.5`

#### Scenario: EBU normalization with targets
- **WHEN** `norm: [:ebu, -16, -1.5, 11]` is passed
- **THEN** the segment is `norm:ebu:-16:-1.5:11`

#### Scenario: Array on a single-part key raises
- **WHEN** `f: [:opus, :mp3]` is passed
- **THEN** an `ArgumentError` is raised naming the keys that take colon-separated parts

### Requirement: Canonical number formatting
Numeric option values SHALL be rendered in the proxy's canonical minimal form: integers as integers; whole floats without a fraction (`30.0` → `30`); fractional floats with at most 3 decimal places and no trailing zeros (`12.5`, never `12.50`); negative zero as `0`; never exponent notation, and never a dangling decimal point. Rendering SHALL reproduce the value's own decimal spelling exactly, including for magnitudes where a double's spacing exceeds 0.001 and for `BigDecimal`s carrying more digits than a double holds. A numeric value that cannot be represented exactly within 3 decimal places SHALL raise an `ArgumentError` rather than being rounded, and a `Numeric` that is not a real number SHALL raise an `ArgumentError` rather than an implementation-level error.

#### Scenario: Whole float loses its fraction
- **WHEN** `t: 30.0` is passed
- **THEN** the segment is `t:30`

#### Scenario: Trailing zeros trimmed
- **WHEN** `gain: -2.50` is passed
- **THEN** the segment is `gain:-2.5`

#### Scenario: Three decimals kept exactly
- **WHEN** `t: 0.125` is passed
- **THEN** the segment is `t:0.125`

#### Scenario: Excess precision raises
- **WHEN** `t: 0.1234` is passed
- **THEN** an `ArgumentError` is raised naming the value and the 3-decimal cap

#### Scenario: Small value never renders as exponent
- **WHEN** `gain: 0.001` is passed
- **THEN** the segment is `gain:0.001` (not `1.0e-03`)

#### Scenario: Negative zero collapses
- **WHEN** `gain: -0.0` is passed
- **THEN** the segment is `gain:0`

### Requirement: String values pass through verbatim
String option values SHALL be used as given without numeric formatting, and opaque-value keys (`dl:`, `cb:`) SHALL render their values verbatim.

#### Scenario: Cache buster
- **WHEN** `cb: "v2"` is passed
- **THEN** the segment is `cb:v2`

#### Scenario: A value carrying a separator raises
- **WHEN** a value contains `/`, `:`, `?`, `#`, whitespace or a control character (`dl: "album/track.mp3"`, `dl: "track#2"`, `dl: "two words.mp3"`)
- **THEN** an `ArgumentError` naming the offending character is raised, rather than a segment that shifts or truncates the signed path

#### Scenario: An empty or nil value raises
- **WHEN** `f: ""` or `br: nil` is passed
- **THEN** an `ArgumentError` is raised rather than an empty or dropped segment

#### Scenario: An empty part inside a multi-part value raises
- **WHEN** `t: ["", 30]` is passed
- **THEN** an `ArgumentError` is raised, rather than `t::30` rendering as though the empty part were the whole value

### Requirement: No client-side domain validation
The gem SHALL NOT validate option value domains or cross-key rules (bitrate ranges, `br` vs `q` exclusivity, fade-fits-trim, …); the proxy is the validator. Rendering-level errors (unknown key, unrenderable number, `raw:` mixed with typed keys) are the only client-side rejections.

#### Scenario: Out-of-domain value is rendered, not rejected
- **WHEN** `br: 999999` is passed
- **THEN** the segment `br:999999` is rendered (the proxy will reject it with a 422)

### Requirement: Spelled-out option key aliases
`url_for` SHALL accept a spelled-out alias for each of the proxy's canonical option keys, resolved
to the canonical key before rendering: `format`→`f`, `bitrate`→`br`, `quality`→`q`,
`sample_rate`→`sr`, `channels`→`ch`, `bit_depth`→`bd`, `trim`→`t`, `fade`→`fade`, `gain`→`gain`,
`normalize`→`norm`, `peak_count`→`pts`, `peak_format`→`pk_fmt`, `download`→`dl`,
`cache_buster`→`cb`. An aliased key SHALL render byte-identically to its canonical spelling.

#### Scenario: Alias renders as the canonical key
- **WHEN** `url_for(source, format: :opus, bitrate: 96)` is called
- **THEN** the options segment is `f:opus/br:96`

#### Scenario: Aliased and canonical calls produce identical URLs
- **WHEN** `url_for(source, format: :opus, trim: [12.5, 30])` and `url_for(source, f: :opus, t: [12.5, 30])` are called
- **THEN** both return the same URL, signature included

#### Scenario: Aliases and canonical keys mix in one call
- **WHEN** `url_for(source, format: :opus, br: 96)` is called
- **THEN** the options segment is `f:opus/br:96`

#### Scenario: Multi-part options keep their array form under an alias
- **WHEN** `normalize: [:ebu, -16, -1.5, 11]` is passed
- **THEN** the segment is `norm:ebu:-16:-1.5:11`

### Requirement: Aliases resolve before defaults merge
Aliases SHALL be resolved before configured `default_options` are merged with per-call keys, so that
the two spellings of one option are one key in the merge rather than two segments.

#### Scenario: Aliased default overridden by a canonical per-call key
- **WHEN** `default_options` is `{ bitrate: 96 }` and `url_for(source, br: 128)` is called
- **THEN** the options segment is `br:128` and contains no second bitrate segment

#### Scenario: Canonical default overridden by an aliased per-call key
- **WHEN** `default_options` is `{ f: :opus, br: 96 }` and `url_for(source, bitrate: 128)` is called
- **THEN** the options segment is `f:opus/br:128`

### Requirement: One option, one spelling per call
Giving both the canonical key and its alias for the same option in a single call SHALL raise an
`ArgumentError` naming both spellings, rather than one silently winning. The same SHALL apply to
`default_options`, rejected at assignment time.

#### Scenario: Both spellings in one call
- **WHEN** `url_for(source, bitrate: 96, br: 128)` is called
- **THEN** an `ArgumentError` naming `bitrate` and `br` is raised

#### Scenario: Both spellings in configured defaults
- **WHEN** `default_options` is assigned `{ bitrate: 96, br: 128 }`
- **THEN** an `ArgumentError` is raised at assignment

### Requirement: Aliases count as typed keys against `raw:`
An alias SHALL be treated as a typed option key wherever typed keys and `raw:` are mutually
exclusive, and the resulting error SHALL name the alias as the caller spelled it rather than the
canonical key. Across call sites the existing precedence is unchanged: an explicit per-call source
of options replaces the configured defaults entirely, in either vocabulary.

#### Scenario: raw mixed with an aliased key
- **WHEN** `url_for(source, raw: "f:opus", bitrate: 96)` is called
- **THEN** an `ArgumentError` naming `raw` and `bitrate` is raised

#### Scenario: Defaults mixing raw with an aliased key
- **WHEN** `default_options` is assigned `{ raw: "f:opus", bitrate: 96 }`
- **THEN** an `ArgumentError` is raised at assignment

#### Scenario: A per-call aliased key replaces a configured raw default
- **WHEN** `default_options` is `{ raw: "f:opus/br:96" }` and `url_for(source, bitrate: 128)` is called
- **THEN** the options segment is `br:128` and carries nothing from the raw default

### Requirement: Durations for the time-valued keys
The keys whose values are seconds (`t`, `fade`) SHALL accept an `ActiveSupport::Duration`, rendered
identically to the equivalent number. A `Duration` given for any other key SHALL raise an
`ArgumentError`.

#### Scenario: Duration renders as seconds
- **WHEN** `url_for(source, t: 30.seconds)` is called
- **THEN** the options segment is `t:30`

#### Scenario: Durations inside a multi-part value
- **WHEN** `fade: [1.5.seconds, 2.seconds]` is passed
- **THEN** the segment is `fade:1.5:2`

#### Scenario: Durations and numbers mix
- **WHEN** `t: [12.5, 1.minute]` is passed
- **THEN** the segment is `t:12.5:60`

#### Scenario: Duration on a key that does not take seconds raises
- **WHEN** `br: 3.seconds` is passed
- **THEN** an `ArgumentError` is raised rather than `br:3` being rendered

### Requirement: Unknown keys still raise, naming both vocabularies
An unrecognized key SHALL continue to raise an `ArgumentError` listing the canonical keys, and the
message SHALL note that spelled-out aliases are also accepted.

#### Scenario: A near-miss alias raises
- **WHEN** `url_for(source, bit_rate: 96)` is called
- **THEN** an `ArgumentError` is raised listing the canonical keys and noting that aliases exist

### Requirement: exp renders as integer seconds
The options renderer SHALL render `exp` as a bare integer unix-seconds value, never decimal or scientific notation, and SHALL raise rather than render a non-Integer. Position within the options segment is not load-bearing: `exp` is a request option, excluded from the proxy's canonical options string and cache key rather than normalized into them, so the builder appends it last and the variant prefix stays byte-identical to the same call without an expiry.

#### Scenario: Integer rendering
- **WHEN** an expiry of 1767225600 is rendered
- **THEN** the segment is exactly `exp:1767225600`

#### Scenario: A non-Integer expiry raises
- **WHEN** `exp` is given a Float, a String or a duration
- **THEN** an `ArgumentError` is raised rather than a segment the proxy would refuse

