## ADDED Requirements

### Requirement: exp renders as integer seconds
The options renderer SHALL render `exp` as a bare integer unix-seconds value, never decimal or scientific notation, positioned like any other option (the proxy normalizes order).

#### Scenario: Integer rendering
- **WHEN** an expiry of 1767225600 is rendered
- **THEN** the segment is exactly `exp:1767225600`
