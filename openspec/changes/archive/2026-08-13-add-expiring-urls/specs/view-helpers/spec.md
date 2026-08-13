## ADDED Requirements

### Requirement: Helpers forward expiry keywords
Every view helper that builds a URL SHALL forward `expires_in:` and `expires_at:` to `url_for` unchanged.

#### Scenario: Audio tag with expiry
- **WHEN** `audioproxy_audio_tag(attachment, format: "opus", expires_in: 30.minutes)` renders
- **THEN** the tag's src carries an `exp:` option 30 minutes ahead of the frozen clock
