## ADDED Requirements

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

### Requirement: Canonical number formatting
Numeric option values SHALL be rendered in the proxy's canonical minimal form: integers as integers; whole floats without a fraction (`30.0` → `30`); fractional floats with at most 3 decimal places and no trailing zeros (`12.5`, never `12.50`); negative zero as `0`; never exponent notation. A numeric value that cannot be represented exactly within 3 decimal places SHALL raise an `ArgumentError` rather than being rounded.

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

### Requirement: No client-side domain validation
The gem SHALL NOT validate option value domains or cross-key rules (bitrate ranges, `br` vs `q` exclusivity, fade-fits-trim, …); the proxy is the validator. Rendering-level errors (unknown key, unrenderable number, `raw:` mixed with typed keys) are the only client-side rejections.

#### Scenario: Out-of-domain value is rendered, not rejected
- **WHEN** `br: 999999` is passed
- **THEN** the segment `br:999999` is rendered (the proxy will reject it with a 422)
