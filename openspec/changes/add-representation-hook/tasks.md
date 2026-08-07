## 1. Configuration

- [ ] 1.1 Add `activestorage_fallback_route` (default `:rails_storage_redirect`) and `audio_content_types` (default empty) to `Audioproxy::Config`
- [ ] 1.2 Validate both at assignment: unknown route name and non-Array/non-String-element set raise `ArgumentError`
- [ ] 1.3 Confirm the credentials allowlist is untouched and neither setting is readable from credentials or ENV

## 2. Route registration

- [ ] 2.1 Register `direct :audioproxy_active_storage` from the railtie via `Rails.application.routes.append`, with no engine and no `config/routes.rb` (D2)
- [ ] 2.2 Verify `direct` composes with `append` — if it does not, stop and amend D2 rather than adding an engine
- [ ] 2.3 Guard against double registration across reloads

## 3. Resolution

- [ ] 3.1 Add `Audioproxy::Rails::RouteResolver` holding the applicability check, fallback and option mapping
- [ ] 3.2 Applicability: `content_type.start_with?("audio/")` or membership in the configured extra set; everything else falls back (D3)
- [ ] 3.3 Unwrap `ActiveStorage::Attachment` and `ActiveStorage::Blob` to a blob and build the URL with configured defaults
- [ ] 3.4 Rescue `UnsupportedServiceError` → fall back, warn once per service class; let `ConfigurationError` propagate (D4)
- [ ] 3.5 Map `disposition: :attachment` to `dl:` using the blob filename; omit `dl:` when the filename would violate the option-value rules, logging at debug; drop all other ActiveStorage URL options (D5)

## 4. Tests

- [ ] 4.1 Dummy app gains a second environment (or equivalent) with the resolver selected, since `resolve_model_to_route` is read at configuration time
- [ ] 4.2 `url_for`, `polymorphic_url` and `link_to` on a blob and on an attachment all produce the signed proxy URL
- [ ] 4.3 Configured `default_options` apply; the resolver-not-selected case still returns Rails' URL
- [ ] 4.4 Non-audio blob falls back; configured extra content type is served; configured fallback route is honoured
- [ ] 4.5 Route survives a route reload (D2) — this is the failure that passes in tests and breaks in development if `append` is not used
- [ ] 4.6 Unsupported service falls back and warns exactly once across three resolutions
- [ ] 4.7 Missing key raises; `unsigned` mode returns an `insecure` URL
- [ ] 4.8 `disposition: :attachment` renders `dl:`; `:inline` renders nothing; a spaced filename omits `dl:` without raising
- [ ] 4.9 `rails_blob_url` and friends still return Rails' URLs with the resolver selected

## 5. Docs

- [ ] 5.1 README: an opt-in section under ActiveStorage — the one-line environment setting, what changes (every blob/attachment URL idiom), what does not (named Rails helpers, non-audio blobs), and the per-environment staging recommendation
- [ ] 5.2 README: the unsupported-service fallback and its warning, tied back to the existing third-rung section
- [ ] 5.3 README Status paragraph

## 6. Gates

- [ ] 6.1 `bin/test` green
- [ ] 6.2 `bin/rubocop` green
- [ ] 6.3 `openspec validate add-representation-hook` passes
- [ ] 6.4 Outside code review per CLAUDE.md, ordered by failure mode: first what a wrongly-resolved route emits, then the fallback paths, then configuration validation. Name previews, direct uploads, mirror services and per-model opt-in as out of scope

## 7. Upstream follow-ups

- [ ] 7.1 Open an issue on the parent proxy for a waveform-*image* format, noting it is what would make an ordinary `ActiveStorage::Previewer` viable and `blob.representation` work with no hacks — the cheapest of the three routes ranked in `design.md`
- [ ] 7.2 Decide whether to revive rails/rails#39283 once this gem has users, naming its two known blockers in any revival
