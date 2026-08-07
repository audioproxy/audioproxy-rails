## Why

Today, proxying an existing app's audio means editing every call site: `url_for(recording.audio)`
becomes `audioproxy_url(recording.audio)`, in views, mailers, serializers and JSON builders. The gem
resolves blobs to source strings but has no way to make the *existing* idiom produce a proxy URL, so
adoption is proportional to how many places an app already names its audio.

`imgproxy-rails` solves the equivalent problem for images without touching call sites, and the
mechanism is Rails' own: ActiveStorage routes a model to a URL through a named route selected by
`config.active_storage.resolve_model_to_route`, and a gem can register its own. imgproxy-rails
declares `direct :imgproxy_active_storage`, checks whether the model is one it can serve, and falls
back to `route_for(:rails_storage_proxy, model, options)` when it is not. An app opts in per
environment — vips in development, imgproxy in production — and `image_tag user.avatar.variant(…)`
is unchanged.

This slice ports that mechanism. It has been deferred three times (`add-gem-core-signing`,
`add-rails-integration`, `add-activestorage-resolution`), each time as "the `blob.representation`
hook, a known rabbit hole", without anyone pinning which rabbit hole. The research settles it — see
`design.md` D1 and its upstream section. The short version: routing **blobs and attachments**
through the proxy is ordinary Rails and carries real transparency; routing **variants** is the
rabbit hole, because ActiveStorage cannot represent audio at all and making it pretend means the app
globally widening `variable_content_types` until Rails believes audio is image-processable, plus
this gem intercepting every operation Rails then performs on it.

**So the variant rung is cut**, deliberately and before implementation, which is the answer to a
question asked three times rather than a fourth deferral. `blob.variant` and `blob.representation`
go on raising Rails' own errors for audio; per-variant options stay expressible as
`audioproxy_url(recording.audio, format: "opus")`. `design.md` records the three upstream routes to
a real fix, ranked, including the one that lands in the parent proxy rather than in Rails.

## What Changes

- **New `direct :audioproxy_active_storage` route**, registered from the railtie (not an engine — see
  `design.md` D2), which an app opts into with
  `config.active_storage.resolve_model_to_route = :audioproxy_active_storage`.
- **Blobs and attachments route through the proxy.** With the resolver selected, `url_for(blob)`,
  `polymorphic_url(attachment)`, `link_to "Download", recording.audio` and every other idiom that
  resolves an ActiveStorage model to a URL return a signed proxy URL built with
  `config.default_options`. No call site changes.
- **Non-audio blobs fall back.** The route serves only blobs whose content type it recognizes as
  audio; everything else is handed to a configurable fallback route (default
  `:rails_storage_redirect`, Rails' own default), so opting in cannot break an app's images or PDFs.
- **`disposition: :attachment` maps to the proxy's `dl:` option**, so an existing
  `url_for(blob, disposition: :attachment)` keeps meaning "download this" through the proxy.
- **Audio on an unsupported storage service falls back rather than raising**, with a warning logged
  once per service class. Opting in is app-wide, and a GCS-hosted blob must not turn every page that
  renders it into a 500.
- **New settings** on `Audioproxy::Config`: the fallback route name and the set of content types
  treated as audio. Initializer-only — the credentials allowlist is unchanged, so
  `rails-config`'s strict-unknown-key rule needs no amendment.
- **Variants and representations stay out.** The gem does not widen
  `ActiveStorage.variable_content_types`, does not set `ActiveStorage.variant_transformer` (a single
  global whose contract is file-in/file-out byte processing, so setting it would break every image
  variant in the host app), and registers no previewer. `recording.audio.variant(…)` goes on raising
  `InvariableError` exactly as it does today.
- README gains a section on opting in, what changes, and what does not.

## Capabilities

### New Capabilities

- `route-resolution`: how ActiveStorage's model-to-URL routing is redirected through the proxy —
  the direct route, what it serves, what it falls back to, and how variants are expressed. Distinct
  from `blob-resolution`, which turns a blob into a *source string* and is consumed here unchanged.

### Modified Capabilities

- `configuration`: adds the fallback route name and the audio content-type set as configurable
  settings, with validation matching the existing strictness (an unknown route name is a typo that
  would otherwise surface as a routing error on an unrelated page).

## Impact

- `lib/audioproxy/rails/railtie.rb` — an initializer appending the direct route.
- `lib/audioproxy/rails/route_resolver.rb` (new) — the applicability check, the fallback, the
  `disposition:` mapping, and the variant unwrapping.
- `lib/audioproxy/config.rb` — two settings and their validation.
- `lib/audioproxy/rails/blob_resolver.rb` — unchanged; consumed as-is.
- `Audioproxy::Signer`, `Audioproxy::UrlBuilder`, `Audioproxy::Options` — untouched. This slice adds
  no URL shape and changes no rendered byte.
- `test/dummy` — needs a second environment or a toggle to exercise both the opted-in and the
  default routing, since `resolve_model_to_route` is set at app configuration time.
- `README.md` — an opt-in section under ActiveStorage.
- No new dependencies. ActiveStorage is already an optional runtime peer, present only when the
  Rails layer loads.
