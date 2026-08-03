## ADDED Requirements

### Requirement: Global configuration block
The gem SHALL expose `Audioproxy.configure` yielding a config object with `endpoint`, `key`, `salt`, `unsigned`, and `default_options` attributes, and `Audioproxy.config` returning the current configuration.

#### Scenario: Configuring the gem
- **WHEN** `Audioproxy.configure { |c| c.endpoint = "https://audio.example.com"; c.key = "aabb"; c.salt = "ccdd" }` is called
- **THEN** `Audioproxy.config.endpoint` returns `"https://audio.example.com"` and the key and salt are stored decoded

### Requirement: Hex key and salt decoded eagerly
The config SHALL accept `key` and `salt` as hex strings and decode them to binary at assignment time. Invalid hex (non-hex characters or odd length) SHALL raise an `ArgumentError` at assignment, not at URL-generation time.

#### Scenario: Valid hex is decoded to binary
- **WHEN** `key` is assigned `"00112233445566778899AABBCCDDEEFF00112233445566778899AABBCCDDEEFF"`
- **THEN** the stored key is the corresponding 32 raw bytes

#### Scenario: Invalid hex fails at assignment
- **WHEN** `key` is assigned `"not-hex"`
- **THEN** an `ArgumentError` is raised naming the attribute

#### Scenario: Odd-length hex fails at assignment
- **WHEN** `salt` is assigned `"abc"`
- **THEN** an `ArgumentError` is raised naming the attribute

### Requirement: Endpoint must be an absolute HTTP(S) base URL
The config SHALL validate that `endpoint` is an absolute `http` or `https` URL, optionally carrying a path prefix, and SHALL raise an `ArgumentError` for anything else. A base URL is scheme, host, optional port and optional path prefix only: the config SHALL reject an endpoint carrying userinfo, a query, or a fragment.

#### Scenario: Endpoint with path prefix accepted
- **WHEN** `endpoint` is assigned `"https://cdn.example.com/audio"`
- **THEN** the assignment succeeds

#### Scenario: Schemeless endpoint rejected
- **WHEN** `endpoint` is assigned `"audio.example.com"`
- **THEN** an `ArgumentError` is raised

#### Scenario: Endpoint with userinfo rejected
- **WHEN** `endpoint` is assigned `"https://user:pass@audio.example.com"`
- **THEN** an `ArgumentError` is raised, and its message does not echo the credentials

#### Scenario: Endpoint with a query or fragment rejected
- **WHEN** `endpoint` is assigned `"https://audio.example.com?foo=bar"` or `"https://audio.example.com#frag"`
- **THEN** an `ArgumentError` is raised

### Requirement: Missing signing material fails loudly
When generating a signed URL (i.e. `unsigned` is not in effect) and `key` or `salt` is absent, the gem SHALL raise a configuration error naming the missing attribute rather than emitting an unverifiable URL.

#### Scenario: Signed URL without a key
- **WHEN** `Audioproxy.url_for("local://a.wav")` is called with no key configured and `unsigned` false
- **THEN** an error is raised naming `key`

#### Scenario: Unsigned mode needs no key
- **WHEN** `unsigned` is true and no key or salt is configured
- **THEN** `Audioproxy.url_for("local://a.wav")` succeeds

### Requirement: Default options
The config SHALL accept `default_options` that are applied to every generated URL unless overridden per call. Keys MAY be given as strings or symbols and SHALL be normalized to symbols. A non-Hash value, a key that is neither String nor Symbol, and an unrecognized option key SHALL each raise an `ArgumentError` at assignment rather than being ignored, because a silently dropped default emits a valid URL for the wrong variant.

#### Scenario: Default raw options applied
- **WHEN** `default_options` is `{ raw: "f:opus" }` and `Audioproxy.url_for("local://a.wav")` is called with no options
- **THEN** the generated URL's options segment is `f:opus`

#### Scenario: String keys are honoured
- **WHEN** `default_options` is `{ "raw" => "f:opus" }` (the shape YAML, ENV and JSON produce)
- **THEN** it is stored as `{ raw: "f:opus" }` and the generated URL's options segment is `f:opus`

#### Scenario: Non-Hash default options rejected
- **WHEN** `default_options` is assigned the string `"f:opus"`
- **THEN** an `ArgumentError` is raised

#### Scenario: Unrecognized option key rejected
- **WHEN** `default_options` is assigned `{ format: "opus" }`
- **THEN** an `ArgumentError` is raised naming the unsupported key
