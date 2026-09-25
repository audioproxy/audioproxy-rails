## MODIFIED Requirements

### Requirement: Typed short-key options
`url_for` SHALL accept the proxy's option keys as keyword arguments — `f:`, `br:`, `q:`, `sr:`, `ch:`, `bd:`, `t:`, `fade:`, `gain:`, `norm:`, `enhance:`, `pts:`, `pk_fmt:`, `dl:`, `cb:` — each rendered as a `key:value` segment, joined with `/`, in the order the caller wrote them.

#### Scenario: Basic typed options
- **WHEN** `url_for(source, f: :opus, br: 96)` is called
- **THEN** the options segment is `f:opus/br:96`

#### Scenario: Symbols and strings render alike
- **WHEN** `f: :opus` or `f: "opus"` is passed
- **THEN** both render `f:opus`

#### Scenario: Unknown key raises
- **WHEN** `url_for(source, bt: 96)` is called
- **THEN** an `ArgumentError` is raised listing the recognized keys

#### Scenario: Enhance preset renders
- **WHEN** `url_for(source, f: :mp3, enhance: :voice)` is called
- **THEN** the options segment is `f:mp3/enhance:voice`

### Requirement: Spelled-out option key aliases
`url_for` SHALL accept a spelled-out alias for each of the proxy's canonical option keys, resolved
to the canonical key before rendering: `format`→`f`, `bitrate`→`br`, `quality`→`q`,
`sample_rate`→`sr`, `channels`→`ch`, `bit_depth`→`bd`, `trim`→`t`, `fade`→`fade`, `gain`→`gain`,
`normalize`→`norm`, `enhance`→`enhance`, `peak_count`→`pts`, `peak_format`→`pk_fmt`,
`download`→`dl`, `cache_buster`→`cb`. An aliased key SHALL render byte-identically to its
canonical spelling.

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

## ADDED Requirements

### Requirement: Enhance presets are not validated client-side
The gem SHALL render any `enhance` value the caller supplies without checking it against the proxy's preset names, consistent with every other option value.

#### Scenario: Unknown preset is rendered
- **WHEN** `enhance: :music` is passed
- **THEN** the segment `enhance:music` is rendered, and the proxy answers `422`
