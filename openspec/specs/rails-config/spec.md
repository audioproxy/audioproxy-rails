# rails-config Specification

## Purpose
TBD - created by archiving change add-rails-integration. Update Purpose after archive.
## Requirements
### Requirement: Railtie sources configuration from credentials
When the gem loads inside a Rails application, a Railtie SHALL populate `Audioproxy.config` from Rails credentials under the `audioproxy` key: `endpoint`, `key`, `salt`, and `unsigned`.

#### Scenario: Credentials configure the gem
- **WHEN** credentials contain `audioproxy: { endpoint: "https://audio.example.com", key: "<hex>", salt: "<hex>" }` and the app boots
- **THEN** `Audioproxy.config` holds that endpoint and the decoded key and salt

#### Scenario: No Rails, no Railtie
- **WHEN** the gem is required outside Rails
- **THEN** no Rails constants are referenced and the core API works as before

### Requirement: ENV fallback with proxy-parity names
For each attribute absent from credentials, the Railtie SHALL fall back to the environment variables `AP_ENDPOINT`, `AP_KEY`, `AP_SALT`, and `AP_ALLOW_INSECURE` (mapping to `unsigned`), matching the proxy's own variable names. Attributes SHALL resolve independently.

#### Scenario: ENV fills a credentials gap
- **WHEN** credentials contain only key and salt, and `AP_ENDPOINT` is set
- **THEN** the endpoint comes from ENV and key/salt from credentials

#### Scenario: Credentials beat ENV
- **WHEN** both credentials and `AP_KEY` define the key
- **THEN** the credentials value wins

### Requirement: Explicit configuration wins
An explicit `Audioproxy.configure` call in an app initializer SHALL override any value sourced from credentials or ENV.

#### Scenario: Initializer override
- **WHEN** the Railtie has applied credentials and an app initializer sets `c.endpoint = "https://other.example.com"`
- **THEN** `Audioproxy.config.endpoint` is `"https://other.example.com"`

### Requirement: Unrecognized credential keys are rejected
The Railtie SHALL raise when credentials under the `audioproxy` key carry a key that is not `endpoint`, `key`, `salt` or `unsigned`, and when one setting is given under two spellings.

#### Scenario: A typo in unsigned does not silently sign
- **WHEN** credentials contain `audioproxy: { endpoint: …, key: …, salt: …, unsinged: true }`
- **THEN** an `ArgumentError` naming `:unsinged` is raised, rather than `unsigned` staying at its default and a signed URL being emitted where the `insecure` segment was meant

#### Scenario: One setting under two spellings
- **WHEN** credentials give both `:endpoint` and `"endpoint"`
- **THEN** an `ArgumentError` naming both spellings is raised

### Requirement: AP_ALLOW_INSECURE is parsed strictly
The Railtie SHALL accept for `unsigned` only a boolean, or one of `1`, `t`, `true`, `0`, `f`, `false` compared case-insensitively, from either credentials or the environment, and SHALL raise on any other value.

#### Scenario: An unrecognized spelling raises
- **WHEN** `AP_ALLOW_INSECURE` is set to `flase`
- **THEN** an `ArgumentError` is raised, rather than the value being cast to `true` and the app emitting unsigned URLs

#### Scenario: The two sources agree on one written character
- **WHEN** credentials contain `unsigned: 1`, which YAML reads as an Integer
- **THEN** `unsigned` is `true`, the same as for `AP_ALLOW_INSECURE=1`

### Requirement: Absent configuration is not an error at boot
The Railtie SHALL NOT raise when credentials and ENV provide nothing; failures surface at URL-generation time via the core's configuration errors.

#### Scenario: Boot without configuration
- **WHEN** an app with no audioproxy credentials or ENV boots
- **THEN** boot succeeds, and a later signed `url_for` call raises the core's missing-key error

