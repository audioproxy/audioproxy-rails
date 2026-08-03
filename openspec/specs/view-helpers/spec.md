# view-helpers Specification

## Purpose
TBD - created by archiving change add-rails-integration. Update Purpose after archive.
## Requirements
### Requirement: audioproxy_url view helper
ActionView SHALL gain an `audioproxy_url(source, **opts)` helper that delegates to `Audioproxy.url_for` with all options passed through.

#### Scenario: Helper available in views
- **WHEN** a view calls `audioproxy_url("local://previews/track.wav", raw: "f:opus")`
- **THEN** it returns exactly what `Audioproxy.url_for` returns for the same arguments

### Requirement: audioproxy_audio_tag view helper
ActionView SHALL gain an `audioproxy_audio_tag(source, **opts, html: {})` helper that builds the URL via `audioproxy_url(source, **opts)` and delegates to Rails' `audio_tag`, passing the `html:` hash as the tag options.

#### Scenario: Audio tag with proxy options and HTML attributes
- **WHEN** a view calls `audioproxy_audio_tag("local://a.wav", raw: "f:opus", html: { controls: true, class: "player" })`
- **THEN** the result is an `<audio>` tag whose `src` is the generated proxy URL, with `controls` and `class="player"` attributes

#### Scenario: Proxy options never leak into the tag
- **WHEN** `audioproxy_audio_tag("local://a.wav", raw: "f:opus")` is called with no `html:`
- **THEN** the rendered tag carries no `raw` attribute

