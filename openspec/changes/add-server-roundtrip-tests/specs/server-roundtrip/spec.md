## ADDED Requirements

### Requirement: Round-trip verification against a running proxy
The suite SHALL include a test group, tagged `:server` and excluded from the default run, that runs
against a proxy at an explicitly pinned version and asserts that URLs built by this gem are accepted
by it. The group SHALL NOT start the proxy: CI runs one as a service container and the README
documents the command for a local run.

#### Scenario: A signed URL renders
- **WHEN** a URL built by `url_for` with the container's key and salt is requested
- **THEN** the proxy answers 200 with audio, rather than refusing the signature

#### Scenario: The signature is load-bearing
- **WHEN** a single byte of a correctly signed URL's path is altered without re-signing
- **THEN** the proxy answers 401 with an `invalid_signature` body, proving the previous scenario
  asserted something

> Both scenarios said 403 when this change was proposed, and were corrected to the observed 401 on
> the harness's first run (design D5). `AudioProxy.ErrorJSON` maps `:invalid_signature` to the 401
> row, and §5 of the proxy's API has no 403 at all — source failures are a blind 404 by design, so
> that a distinct status cannot become an existence oracle.

#### Scenario: An unsigned URL renders under AP_ALLOW_INSECURE
- **WHEN** the container runs with `AP_ALLOW_INSECURE` and a URL built with `unsigned: true` is
  requested
- **THEN** the proxy answers 200

#### Scenario: The default run needs no container
- **WHEN** `bin/test` runs on a machine with no Docker and no network
- **THEN** it passes, and the `:server` group is skipped rather than failed

#### Scenario: Asking for the group and not supplying a proxy is a failure
- **WHEN** the group is pointed at a proxy address and nothing answers there
- **THEN** it fails rather than skipping, because a run that was asked to exercise a proxy and
  silently exercised nothing is the one outcome the group must never produce

### Requirement: Expiry verified end to end
The `:server` group SHALL verify that an expiring URL behaves at a real proxy as
`add-expiring-urls` claims, retiring that change's deferred task 3.4.

#### Scenario: Live before expiry
- **WHEN** a URL built with `expires_in:` is requested before its expiry
- **THEN** the proxy answers 200, identically to a URL with no expiry

#### Scenario: Gone after expiry
- **WHEN** the same URL is requested after its `exp` has passed
- **THEN** the proxy answers 410 — not 401 (the wrong refusal) and not 422 (the proxy failing to
  parse `exp` at all, which would make every other expiry scenario here vacuous)

#### Scenario: The boundary is where the gem says it is
- **WHEN** a URL whose `exp` names the current second is requested
- **THEN** the proxy still serves it, confirming the exclusive boundary the gem reads from
  `expiry.ex` and encodes in `add-expiring-urls` D5

### Requirement: The proxy version under test is pinned and visible
The suite SHALL name an explicit proxy version rather than tracking `latest`, and SHALL verify at
run time that the proxy answering is that version, refusing to run against any other. A failure
caused by a version mismatch SHALL name both the version that answered and the one expected.

#### Scenario: The suite reports what actually answered
- **WHEN** the group is pointed at a proxy of a different version from the pinned one
- **THEN** it fails naming both versions, rather than running and attributing the resulting
  disagreement to this gem

#### Scenario: An upstream release cannot silently change this suite
- **WHEN** the proxy publishes a new release
- **THEN** this suite keeps testing the pinned tag until a commit here advances it
