## MODIFIED Requirements

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
