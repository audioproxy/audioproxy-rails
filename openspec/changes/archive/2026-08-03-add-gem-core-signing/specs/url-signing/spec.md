## ADDED Requirements

### Requirement: HMAC-SHA256 signature over salt-prefixed rest-of-path
The signer SHALL compute `base64url(HMAC-SHA256(key, salt ‖ rest_of_path))` without padding, where `rest_of_path` is the exact byte sequence of the URL path after the signature segment, leading `/` included, and key and salt are the decoded binary values.

#### Scenario: Known-answer vector one
- **WHEN** signing `/f:opus/br:96/plain/s3://masters/2026/piece-final.wav` with key `0011 2233 4455 6677 8899 AABB CCDD EEFF` ×2 (hex) and salt `FFEE DDCC BBAA 9988 7766 5544 3322 1100` (hex)
- **THEN** the signature is exactly `zfLTfPPhQ8kdeYYJOdagqPfog2nFk7KzDFUjtRAf_Ns`

#### Scenario: Known-answer vector two
- **WHEN** signing `/info/plain/s3://b/k.wav` with the same key and salt
- **THEN** the signature is exactly `U6nyFdkSvjNo2mlBbJMGk1nwISbdcnEGlgKSWKBfKT4`

#### Scenario: Output is unpadded base64url
- **WHEN** any path is signed
- **THEN** the signature is 43 characters matching `[A-Za-z0-9_-]+` with no trailing `=`

### Requirement: Paths without a leading slash are rejected
The signer SHALL raise an error when given a `rest_of_path` that does not begin with `/`, because such a signature could never verify at the proxy.

#### Scenario: Missing leading slash
- **WHEN** signing `f:opus/plain/local://a.wav`
- **THEN** an error is raised

### Requirement: Unsigned mode emits the literal insecure segment
When `unsigned` is in effect, the URL's signature segment SHALL be the literal string `insecure` (parity with the proxy's `AP_ALLOW_INSECURE` mode) and no HMAC SHALL be computed.

#### Scenario: Unsigned URL shape
- **WHEN** `Audioproxy.url_for("local://a.wav", unsigned: true)` is called against endpoint `https://audio.example.com`
- **THEN** the URL path begins `/insecure/` followed by the options segment
