## ADDED Requirements

### Requirement: Route resolution settings
`Audioproxy::Config` SHALL expose two settings governing ActiveStorage route resolution: the name of
the route non-audio and unservable models fall back to (defaulting to `:rails_storage_redirect`), and
an additional set of content types to treat as audio beyond the `audio/` prefix (defaulting to
empty). Both SHALL be settable only through `Audioproxy.configure`; the credentials allowlist is
unchanged, so neither is readable from credentials or ENV.

#### Scenario: Fallback route default
- **WHEN** a fresh configuration is inspected
- **THEN** the fallback route is `:rails_storage_redirect` and the additional audio content types are empty

#### Scenario: Fallback route configured
- **WHEN** `config.activestorage_fallback_route = :rails_storage_proxy` is assigned
- **THEN** the setting takes that value and non-audio models resolve through that route

#### Scenario: Additional content types configured
- **WHEN** `config.audio_content_types = %w[application/ogg]` is assigned
- **THEN** a blob of that content type is treated as audio by the route resolver

#### Scenario: Settings are not readable from credentials
- **WHEN** an `audioproxy:` credentials block contains `activestorage_fallback_route`
- **THEN** the existing unrecognized-credential-key rule rejects it, as it does any other unknown key

### Requirement: Route resolution settings are validated at assignment
An unrecognized fallback route name and a non-Array or non-String content-type set SHALL raise
`ArgumentError` at assignment, in keeping with the rest of the configuration object. A typo in either
would otherwise surface as a routing error on a page unrelated to the line that caused it.

#### Scenario: Unknown fallback route rejected
- **WHEN** `config.activestorage_fallback_route = :rails_storage_prxy` is assigned
- **THEN** an `ArgumentError` is raised naming the accepted route names

#### Scenario: Malformed content-type set rejected
- **WHEN** `config.audio_content_types = "application/ogg"` is assigned
- **THEN** an `ArgumentError` is raised naming the expected shape
