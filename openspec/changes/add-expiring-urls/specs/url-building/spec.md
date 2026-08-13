## ADDED Requirements

### Requirement: Expiry keywords on url_for
`url_for` SHALL accept `expires_in:` (ActiveSupport duration or positive Integer seconds, added to the current time at build time) and `expires_at:` (Time-like or Integer unix timestamp, used as-is), mutually exclusive, rendering an `exp:<unix-seconds>` option segment; validation SHALL raise at call time for both keywords together, a non-positive `expires_in`, an `expires_at` at or before the current time, or an uncoercible type.

#### Scenario: Duration arithmetic at build time
- **WHEN** `url_for(source, expires_in: 1.hour)` is called with the clock frozen
- **THEN** the options segment contains `exp:` with exactly the frozen time plus 3600 seconds

#### Scenario: Both keywords raise
- **WHEN** `expires_in:` and `expires_at:` are both given
- **THEN** an ArgumentError is raised at the call site, and no URL is produced

#### Scenario: Past expires_at raises
- **WHEN** `expires_at:` is at or before the current time
- **THEN** an error is raised rather than minting an already-dead URL
