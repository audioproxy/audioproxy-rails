## ADDED Requirements

### Requirement: Optional global expiry default
Configuration SHALL accept `expires_in` (nil by default, meaning URLs carry no expiry); when set, every built URL applies it unless the call site passes its own `expires_in:`/`expires_at:`, and a per-call `expires_in: nil` SHALL opt that URL out of the global default.

#### Scenario: Global default applies
- **WHEN** `config.expires_in = 1.hour` and `url_for(source)` is called
- **THEN** the URL carries `exp:` one hour ahead

#### Scenario: Per-call opt-out
- **WHEN** the global default is set and the call passes `expires_in: nil`
- **THEN** the URL carries no `exp:` option
