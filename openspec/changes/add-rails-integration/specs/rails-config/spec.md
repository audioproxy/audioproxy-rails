## ADDED Requirements

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

### Requirement: Absent configuration is not an error at boot
The Railtie SHALL NOT raise when credentials and ENV provide nothing; failures surface at URL-generation time via the core's configuration errors.

#### Scenario: Boot without configuration
- **WHEN** an app with no audioproxy credentials or ENV boots
- **THEN** boot succeeds, and a later signed `url_for` call raises the core's missing-key error
