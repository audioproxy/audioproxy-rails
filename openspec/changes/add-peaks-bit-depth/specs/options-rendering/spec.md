## MODIFIED Requirements

### Requirement: Typed short-key options
`url_for` SHALL accept the proxy's option keys as keyword arguments — `f:`, `br:`, `q:`, `sr:`, `ch:`, `bd:`, `t:`, `fade:`, `gain:`, `norm:`, `pts:`, `pk_fmt:`, `pk_bits:`, `dl:`, `cb:` — each rendered as a `key:value` segment, joined with `/`, in the order the caller wrote them.

#### Scenario: Basic typed options
- **WHEN** `url_for(source, f: :opus, br: 96)` is called
- **THEN** the options segment is `f:opus/br:96`

#### Scenario: Symbols and strings render alike
- **WHEN** `f: :opus` or `f: "opus"` is passed
- **THEN** both render `f:opus`

#### Scenario: Unknown key raises
- **WHEN** `url_for(source, bt: 96)` is called
- **THEN** an `ArgumentError` is raised listing the recognized keys

#### Scenario: Peaks bit depth renders
- **WHEN** `url_for(source, f: :peaks, pk_bits: 8)` is called
- **THEN** the options segment is `f:peaks/pk_bits:8`

### Requirement: Spelled-out option key aliases
`url_for` SHALL accept a spelled-out alias for each of the proxy's canonical option keys, resolved
to the canonical key before rendering: `format`→`f`, `bitrate`→`br`, `quality`→`q`,
`sample_rate`→`sr`, `channels`→`ch`, `bit_depth`→`bd`, `trim`→`t`, `fade`→`fade`, `gain`→`gain`,
`normalize`→`norm`, `peak_count`→`pts`, `peak_format`→`pk_fmt`, `peak_bits`→`pk_bits`,
`download`→`dl`, `cache_buster`→`cb`. An aliased key SHALL render byte-identically to its
canonical spelling.

`peak_bits` is deliberately not `bit_depth`, which is already taken by `bd` and means the sample format of encoded output. The two are different concerns that would otherwise share one spelling.

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

#### Scenario: Peak aliases stay distinct from bit depth
- **WHEN** `url_for(source, format: :peaks, peak_bits: 8)` and `url_for(source, f: :peaks, pk_bits: 8)` are called
- **THEN** both return the same URL, and `bit_depth: 8` renders `bd:8` instead, which is a different segment

## ADDED Requirements

### Requirement: Peaks bit depth is not validated client-side
The gem SHALL render any `pk_bits` value the caller supplies without checking it against the proxy's domain of `8` and `16`, consistent with every other option value.

#### Scenario: Out-of-domain peak bit depth is rendered
- **WHEN** `pk_bits: 24` is passed
- **THEN** the segment `pk_bits:24` is rendered, and the proxy answers `422`
