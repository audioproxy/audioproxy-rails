## ADDED Requirements

### Requirement: Opt-in direct route
The gem SHALL register a `direct :audioproxy_active_storage` route from its railtie, so an app can
select it with `config.active_storage.resolve_model_to_route = :audioproxy_active_storage`. The
route SHALL be registered in a way that survives development route reloading, and the gem SHALL NOT
contain a `config/routes.rb` or a Rails engine.

#### Scenario: Route available after boot
- **WHEN** the dummy app boots with the gem loaded
- **THEN** the `audioproxy_active_storage` direct route is defined in the application's route set

#### Scenario: Route survives a reload
- **WHEN** the application's routes are reloaded
- **THEN** the `audioproxy_active_storage` route is still defined and still resolves

#### Scenario: No engine artifacts added
- **WHEN** the repository is inspected
- **THEN** no `config/routes.rb` exists at the gem root and no `Rails::Engine` subclass is defined

### Requirement: Blobs and attachments resolve to proxy URLs
An audio blob or attachment SHALL resolve to `Audioproxy.url_for(blob)` with the configured
`default_options` applied, whenever the resolver is selected, through every idiom that routes an
ActiveStorage model to a URL.

#### Scenario: url_for on an attachment
- **WHEN** `url_for(recording.audio)` is called in a view with the resolver selected
- **THEN** the result is the signed proxy URL for the attachment's blob

#### Scenario: Existing call sites are unchanged
- **WHEN** a template contains `link_to "Download", recording.audio`
- **THEN** the rendered `href` is the signed proxy URL, with no change to the template

#### Scenario: Configured defaults apply
- **WHEN** `default_options` is `{ f: :opus, br: 96 }` and a blob is resolved through the route
- **THEN** the URL's options segment contains `f:opus` and `br:96`

#### Scenario: Resolver not selected
- **WHEN** `config.active_storage.resolve_model_to_route` is left at its default
- **THEN** `url_for(recording.audio)` returns the Rails storage URL it returned before the gem was installed

### Requirement: Non-audio models fall back
The route SHALL serve only models whose blob content type begins with `audio/` or appears in the
configured additional content-type set, and SHALL hand every other model to the configured fallback
route, which defaults to `:rails_storage_redirect`.

#### Scenario: Image blob falls back
- **WHEN** `url_for(user.avatar)` is called for an `image/png` blob with the resolver selected
- **THEN** the result is the Rails storage URL produced by the fallback route, not a proxy URL

#### Scenario: Configured extra content type is served
- **WHEN** `application/ogg` is added to the configured audio content types and such a blob is resolved
- **THEN** the result is a proxy URL

#### Scenario: Configured fallback route is used
- **WHEN** the fallback route is configured as `:rails_storage_proxy` and a non-audio blob is resolved
- **THEN** the result is the proxy-mode Rails storage URL

### Requirement: Unsupported storage services fall back with a warning
An audio blob on a storage service the gem cannot express SHALL be handed to the fallback route
rather than raising, and a warning naming the service class SHALL be logged once per service class.
Selecting the resolver is app-wide and retroactive, so a blob on an unsupported service must not
turn a working page into an error.

#### Scenario: GCS-hosted audio falls back
- **WHEN** an audio blob on a GCS service is resolved through the route
- **THEN** the result is the fallback route's URL and no error is raised

#### Scenario: Warning logged once
- **WHEN** three blobs on the same unsupported service are resolved in one process
- **THEN** the warning naming that service class is logged once

### Requirement: Missing signing material still raises
A `ConfigurationError` from missing key or salt SHALL propagate out of the route rather than falling
back. An app that has selected the resolver but configured no signing material must fail visibly, not
serve un-proxied URLs while believing it is proxying.

#### Scenario: No key configured
- **WHEN** an audio blob is resolved with the resolver selected and no key or salt configured
- **THEN** a `ConfigurationError` is raised

#### Scenario: Unsigned mode needs no key
- **WHEN** `unsigned` is true and an audio blob is resolved
- **THEN** a URL carrying the literal `insecure` signature segment is returned

### Requirement: Disposition maps to the download option
`disposition: :attachment` SHALL be carried through as the proxy's `dl:` option using the blob's
filename. When the filename would violate the gem's option-value rules, `dl:` SHALL be omitted rather
than raising or being re-encoded. Other ActiveStorage URL options SHALL be dropped.

#### Scenario: Attachment disposition
- **WHEN** `url_for(recording.audio, disposition: :attachment)` is called for a blob named `piece.wav`
- **THEN** the URL's options segment contains `dl:piece.wav`

#### Scenario: Inline disposition adds nothing
- **WHEN** `url_for(recording.audio, disposition: :inline)` is called
- **THEN** the URL carries no `dl:` segment

#### Scenario: Awkward filename omits the option
- **WHEN** the blob's filename contains a space or a slash
- **THEN** a URL is returned with no `dl:` segment, and no error is raised

### Requirement: Variants and representations are out of scope and stay raising
The gem SHALL NOT make audio blobs variable or representable, and SHALL NOT widen
`ActiveStorage.variable_content_types` or register a variant transformer or previewer. An audio
blob's `variant` and `representation` continue to raise Rails' own `InvariableError` and
`UnrepresentableError`. Per-variant proxy options are expressed by passing options to
`audioproxy_url`, which is the vocabulary this gem already has.

#### Scenario: Audio blobs stay invariable
- **WHEN** `recording.audio.blob.variant(format: "opus")` is called with the gem loaded and the resolver selected
- **THEN** Rails raises `ActiveStorage::InvariableError`, unchanged by this gem

#### Scenario: variable_content_types is untouched
- **WHEN** the application boots with the gem loaded
- **THEN** `ActiveStorage.variable_content_types` contains exactly what the application configured, with no audio types added by the gem

### Requirement: Named Rails storage helpers are unaffected
`rails_blob_url`, `rails_storage_proxy_url` and `rails_storage_redirect_url` SHALL continue to
return Rails' own URLs regardless of the selected resolver, so a call site can opt out explicitly.

#### Scenario: Explicit Rails helper bypasses the proxy
- **WHEN** `rails_blob_url(recording.audio)` is called with the resolver selected
- **THEN** the result is the Rails storage URL, not a proxy URL
