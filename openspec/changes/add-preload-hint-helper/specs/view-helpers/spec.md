## ADDED Requirements

### Requirement: audioproxy_preload_link_tag view helper
ActionView SHALL gain an `audioproxy_preload_link_tag(source, **opts, html: {})` helper that builds
the URL via `audioproxy_url(source, **opts)` and delegates to ActionView's `preload_link_tag`,
passing the `html:` hash as the tag options.

#### Scenario: Preload tag with proxy options and link attributes
- **WHEN** a view calls `audioproxy_preload_link_tag("local://a.wav", format: "opus", bitrate: 96, html: { fetchpriority: "high" })`
- **THEN** the result is a `<link rel="preload">` tag whose `href` is the generated proxy URL, carrying `fetchpriority="high"`

#### Scenario: Attachment source
- **WHEN** a view calls `audioproxy_preload_link_tag(@recording.audio, format: "opus")`
- **THEN** the attachment resolves to a source string and the tag's `href` is the proxy URL built from it

#### Scenario: Non-Hash html bucket rejected
- **WHEN** a view calls `audioproxy_preload_link_tag("local://a.wav", html: "controls")`
- **THEN** an `ArgumentError` is raised naming the `html:` argument

### Requirement: Preload hints declare an audio destination
The emitted tag SHALL carry `as="audio"` unless the caller supplies a non-blank `as:` in `html:`. A
proxy URL ends in an encoded source segment with no file extension, so ActionView's extension-based
inference cannot supply one, and a `rel=preload` without a destination is a tag browsers decline to
act on. A blank `as:` — `nil`, `false` or `""` — SHALL raise an `ArgumentError` rather than count as
an override, because it produces exactly that inert tag.

#### Scenario: Default destination
- **WHEN** a view calls `audioproxy_preload_link_tag("local://a.wav")`
- **THEN** the emitted tag carries `as="audio"`

#### Scenario: Caller overrides the destination
- **WHEN** a view calls `audioproxy_preload_link_tag("local://a.wav", html: { as: "fetch" })`
- **THEN** the emitted tag carries `as="fetch"` and no second `as` attribute

#### Scenario: Blank destination rejected
- **WHEN** a view calls `audioproxy_preload_link_tag("local://a.wav", html: { as: nil })`, or with `false` or `""`
- **THEN** an `ArgumentError` is raised and no tag is rendered

### Requirement: Preload hints introduce no crossorigin of their own
The helper SHALL NOT add a `crossorigin` attribute, matching what `audioproxy_audio_tag` emits, so
the two agree by default. A preload whose `crossorigin` disagrees with the element consuming it
causes the browser to fetch the variant twice.

Two caller-supplied values are not defaults and are settled explicitly. `crossorigin: true` SHALL
raise an `ArgumentError`, because ActionView renders it `"anonymous"` on a preload link and `"true"`
on an `<audio>` tag, so writing it in both places produces the very mismatch this requirement exists
to prevent. `as: "font"` reaches ActionView's own rule of adding `crossorigin="anonymous"` to font
preloads; on an audio URL that is a caller error, and it is left to ActionView rather than guarded
against here.

#### Scenario: No crossorigin by default
- **WHEN** a view calls `audioproxy_preload_link_tag("local://a.wav")`
- **THEN** the emitted tag carries no `crossorigin` attribute

#### Scenario: Boolean crossorigin rejected
- **WHEN** a view calls `audioproxy_preload_link_tag("local://a.wav", html: { crossorigin: true })`
- **THEN** an `ArgumentError` is raised naming the two renderings

#### Scenario: An explicit crossorigin string agrees across both helpers
- **WHEN** a view calls both helpers with `html: { crossorigin: "anonymous" }`
- **THEN** both emitted tags carry `crossorigin="anonymous"`

### Requirement: Proxy options never appear as link attributes
Proxy options passed to the helper SHALL NOT reach the emitted tag, and `html:` entries SHALL NOT
reach the URL builder.

#### Scenario: Options do not leak into the tag
- **WHEN** a view calls `audioproxy_preload_link_tag("local://a.wav", raw: "f:opus")`
- **THEN** the rendered tag carries no `raw` attribute

#### Scenario: Unknown proxy option raises rather than becoming an attribute
- **WHEN** a view calls `audioproxy_preload_link_tag("local://a.wav", bitrat: 96)`
- **THEN** an `ArgumentError` is raised and no tag is rendered

### Requirement: The preload href is byte-identical to the audio tag's src
For the same source and the same options, the `href` emitted by `audioproxy_preload_link_tag` SHALL
equal the `src` emitted by `audioproxy_audio_tag`, including when the configured endpoint carries a
path prefix. A differing byte is a different variant, a different cache key, and a preload the
browser never matches to the element that needs it.

#### Scenario: Hint and element agree
- **WHEN** a view calls `audioproxy_preload_link_tag(source, format: "opus", bitrate: 96)` and `audioproxy_audio_tag(source, format: "opus", bitrate: 96)`
- **THEN** the `href` of the first equals the `src` of the second, byte for byte

#### Scenario: Endpoint path prefix survives the tag helper
- **WHEN** the endpoint is `https://cdn.example.com/audio` and a preload tag is rendered
- **THEN** the `href` equals `audioproxy_url` for the same arguments, with no asset-pipeline rewriting applied to it
