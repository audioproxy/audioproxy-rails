## ADDED Requirements

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
