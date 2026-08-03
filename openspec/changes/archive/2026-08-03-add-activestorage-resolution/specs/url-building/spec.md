## MODIFIED Requirements

### Requirement: Module-level entry point is Rails-free
`Audioproxy.url_for` SHALL be usable with only the gem's own files loaded (no Rails, no ActiveSupport), so it works in jobs, mailers, and serializers of any Ruby program. Non-String sources SHALL be resolved through a resolver registration hook: the Rails layer registers the ActiveStorage blob resolver when ActiveStorage is present, and the core itself SHALL reference no ActiveStorage constants. With no resolver registered, a non-String source raises an `ArgumentError`.

#### Scenario: Standalone require
- **WHEN** a plain Ruby script requires `audioproxy` and configures endpoint/key/salt
- **THEN** `Audioproxy.url_for` returns a correct URL with no Rails constants defined

#### Scenario: Non-String source without a resolver
- **WHEN** `Audioproxy.url_for(Object.new)` is called outside Rails
- **THEN** an `ArgumentError` is raised

#### Scenario: Registered resolver handles blobs
- **WHEN** the Rails layer has registered the blob resolver and `url_for` receives a blob
- **THEN** the blob is resolved to a source string and the URL is built from it
