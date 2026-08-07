## Context

### What imgproxy-rails actually does

The research this change was asked to rest on, in full, because every decision below is either a
port of it or a deliberate departure.

`imgproxy-rails` is four small files. `lib/imgproxy-rails/engine.rb` is an empty `Rails::Engine`,
present only so that `config/routes.rb` is loaded into the host app's route set. That file is the
whole mechanism:

```ruby
Rails.application.routes.draw do
  direct :imgproxy_active_storage do |model, options|
    if ImgproxyRails::Helpers.applicable_variation?(model)
      transformations = model.variation.transformations
      Imgproxy.url_for(model.blob, ImgproxyRails::Transformer.call(transformations))
    else
      route_for(:rails_storage_proxy, model, options)
    end
  end
end
```

`applicable_variation?` is a guard, not a conversion:

```ruby
def self.applicable_variation?(model)
  return false if !model.respond_to?(:variation)

  content_type = model.try(:blob)&.content_type
  content_type&.start_with?("image/") ||
    content_type&.start_with?("video/") ||
    content_type == "application/pdf"
end
```

`Transformer` maps ActiveStorage's image-processing vocabulary onto imgproxy's option vocabulary —
`resize_to_limit: [w, h]` → `{width:, height:}`, `resize_to_fill:` → `{resizing_type: :fill}`, a
`GRAVITY` table, a `PASSTHROUGH_OPTIONS` set for keys both sides spell the same — and reserves
`imgproxy_options:` inside the transformation hash as an escape hatch that is merged **last**, so it
beats anything the mapping produced.

The app opts in per environment:

```ruby
# config/environments/development.rb
config.active_storage.resolve_model_to_route = :rails_storage_proxy
# config/environments/production.rb
config.active_storage.resolve_model_to_route = :imgproxy_active_storage
```

Underneath, this is Rails' own seam. ActiveStorage's engine declares
`resolve("ActiveStorage::Variant") { |variant, options| route_for(ActiveStorage.resolve_model_to_route, variant, options) }`
and the same for `VariantWithRecord`, `Preview`, `Attachment` and `Blob`. So `url_for(model)`,
`polymorphic_url(model)`, and every helper built on them — `image_tag`, `link_to` — flow through
whichever named route that setting points at.

### Where the port breaks, and why this was called a rabbit hole three times

The mechanism ports cleanly. The *subject* does not.

imgproxy-rails' value is that `image_tag user.avatar.variant(resize_to_limit: [100, 100])` — code
that already exists in thousands of apps — keeps working and starts going through imgproxy. That
value depends on ActiveStorage having an image-variant vocabulary that apps already use.

**ActiveStorage has no audio vocabulary, and cannot make an audio variant at all.** `blob.variant`
raises `ActiveStorage::InvariableError` unless the blob is `variable?`, which means its content type
is in `config.active_storage.variable_content_types` — an image list. `blob.representation` calls
`variant` when variable, `preview` when previewable, and raises `UnrepresentableError` otherwise;
audio is neither. So there is no existing call site to keep working, no transformation hash to
translate, and `Transformer` has no analogue: this gem would be inventing an audio variant
vocabulary and then mapping its own invention onto its own option keys.

That is the rabbit hole, named. It is not the route resolver.

### What is left once the rabbit hole is drained

The `resolve` hook covers `ActiveStorage::Blob` and `ActiveStorage::Attachment`, not just variants.
Those *do* have existing call sites in audio apps, today, that work: `url_for(recording.audio)`,
`link_to "Download", recording.audio`, `polymorphic_url` inside a serializer. They currently resolve
to `rails_storage_redirect` — a Rails route that 302s to the file. Pointing them at the proxy
instead is real transparency, needs no vocabulary, needs no `variable_content_types` widening, and
is the same four lines of `direct` route.

## Goals / Non-Goals

**Goals:**

- An opt-in `direct :audioproxy_active_storage` route that turns existing blob and attachment URL
  call sites into proxy URLs with no code change.
- Safe fallback for everything the proxy cannot serve: non-audio content types, unsupported storage
  services, and models the route does not recognize.
- `disposition:` carried through to the proxy's `dl:` option, so the one ActiveStorage URL option
  that has a proxy counterpart keeps its meaning.
- A settled, written answer to "which rabbit hole", so this is not deferred a fourth time.

**Non-Goals:**

- Translating an ActiveStorage transformation vocabulary into proxy options. There is nothing to
  translate from (Context, above). `Transformer` has no port.
- Widening `config.active_storage.variable_content_types` on the app's behalf. It is a global
  setting with effects far outside this gem — `blob.representable?` starts answering true, and any
  other code or gem that branches on it changes behaviour. The app widens it or does not get the
  variant rung.
- Processing an audio representation. There is no processor; see D6.
- Previews (`ActiveStorage::Preview`) and `preview_image`. A waveform image would be the obvious
  candidate and the proxy renders peaks rather than images, so there is nothing to point a preview at.
- Changing what `rails_blob_url`, `rails_storage_proxy_url` or `rails_storage_redirect_url` return.
  Those are named helpers an app calls deliberately, and they stay Rails' — which makes them the
  per-call-site escape hatch from this slice.
- Direct uploads, mirror services, GCS/Azure. Unchanged from `add-activestorage-resolution`.

## Decisions

### D1 — Blobs and attachments only. The variant rung is cut. **[Amended]**

**Rung A**, blobs and attachments: the route resolves `ActiveStorage::Blob` and
`ActiveStorage::Attachment` to `Audioproxy.url_for(blob)` with configured `default_options`. This
is the change.

**Rung B**, variants — `recording.audio.variant(audioproxy: { format: "opus" })` — was specified
here and is **cut**, before implementation, for the reasons below. It is the literal
`blob.representation` hook the three deferral notes named, so cutting it is the answer to a question
that has been asked three times, not a fourth deferral.

The cut rests on what Rails 8.1.3.1 actually does, read from the installed gem rather than from
release notes:

- `Blob#variant` raises `InvariableError` unless `ActiveStorage.variable_content_types.include?(content_type)`,
  and that list is images. So Rung B requires the *app* to widen a global setting until Rails
  believes audio is image-processable.
- `Blob#representation` dispatches `previewable?` first, then `variable?`, and raises
  `UnrepresentableError` otherwise. Audio is neither.
- `ActiveStorage.variant_transformer` does exist as a `mattr_accessor` and is therefore technically
  swappable — but it is set once, globally, from `config.active_storage.variant_processor`
  (`:vips`, `:mini_magick`, `:disabled`), and its contract is
  `transform(file, format:) { |tempfile| }`: **it takes a downloaded file and returns a processed
  file.** It is a byte-processing seam. A URL-building proxy has no bytes and wants none, and a gem
  that set this global would break every image variant in the host app.

So Rung B would have meant: the app lies to Rails about audio being variable, and this gem then
intercepts every operation Rails performs on variable things (D6) so none of them reaches an image
processor. Two layers of pretending, to buy a call site — `recording.audio.variant(…)` — that exists
in no application today, because Rails has never been able to produce it.

Rung A needs none of that. It is Rails' own `resolve_model_to_route` seam used exactly as intended,
and it upgrades call sites that *do* exist.

The upstream landscape, since this is the kind of gap that is better fixed in Rails than worked
around here, is recorded under "Upstream: what it would take to do this properly" below.

### D2 — Register the route from the railtie, not from an engine

imgproxy-rails uses an empty `Rails::Engine` solely to get a `config/routes.rb` auto-loaded. This
repo's architecture forbids that: "Everything Rails-facing lives under `Audioproxy::Rails` and hooks
in through a railtie, not an engine (no routes, no `app/`, no migrations)" — and `gem-packaging`
pins it as a requirement, asserting no `config/routes.rb` exists at the gem root.

`Rails.application.routes.append { direct :audioproxy_active_storage do … end }` from a railtie
initializer registers the same route without the engine. `append` blocks are re-run on every route
reload, which is what makes this survive development's reloading — a plain `routes.draw` inside an
initializer does not, and would vanish on the first reload in dev while working perfectly in the
tests. That failure mode is exactly the kind this repo's testing discipline exists to catch, so it
gets an explicit reload test rather than a comment (Tasks 4.5).

This is a departure from the reference implementation, taken because the architecture constraint is
binding and the mechanism does not need the engine. If `append` turns out not to support `direct` —
the DSL method lives on the mapper and `append` blocks are evaluated in mapper context, which should
mean it does, but "should" is not a standard this repo accepts — the fallback is to raise it as a
`design.md` amendment rather than quietly adding an engine.

### D3 — Non-audio falls back to a configurable route, defaulting to Rails' own default

`resolve_model_to_route` is app-wide: opting in points *every* ActiveStorage model URL at this
route, including avatars and PDFs. The route must therefore serve audio and hand back everything
else, exactly as `applicable_variation?` does.

imgproxy-rails falls back to `:rails_storage_proxy` unconditionally. That is wrong for a port,
because it silently changes non-audio URLs from redirect-mode to proxy-mode for any app whose
default was the former. The fallback here defaults to `:rails_storage_redirect`, Rails' own default,
and is configurable for apps that prefer proxy mode.

Applicability is `blob.content_type.start_with?("audio/")`, plus a configurable extra set. The extra
set exists because the `audio/` prefix is not exhaustive — `application/ogg` is the common miss —
and because guessing the full list here would be this gem asserting a content-type taxonomy it does
not own.

### D4 — An unsupported storage service falls back and warns; a missing key still raises

Two failure modes reach this route, and they get opposite treatment.

**Unsupported service** (`Audioproxy::UnsupportedServiceError`, from a GCS or Mirror blob): fall
back, and log a warning once per service class. Rationale: opting in is app-wide and retroactive,
so raising would turn every page rendering a GCS-hosted audio blob into a 500 the moment the flag
flips. The fallback URL is *correct* — Rails serves the file — merely un-proxied, which is a
different category from this gem's usual "plausible-but-wrong URL" hazard. Warning once per service
class rather than per request keeps it visible without flooding logs.

**Missing key or salt** (`Audioproxy::ConfigurationError`): raise. It is deterministic, it fires on
the first request in development, and the fix is one line of credentials. Swallowing it would mean
an app that believes it is proxying and never is — with no 403 to discover, because no proxy URL is
ever generated. This is the asymmetry worth stating: fall back from what this gem *cannot* express,
raise on what the operator has *not configured*.

### D5 — `disposition: :attachment` maps to `dl:`

`url_for(blob, disposition: :attachment)` is an existing ActiveStorage idiom, and the proxy has a
counterpart: `dl:` sets `Content-Disposition: attachment` (API v1 §3.4). The route maps it, using
the blob's `filename` as the value.

The `dl:` value must survive the gem's own option-value rules, which reject whitespace and path
separators — `add-options-rendering` is explicit that a `dl:` filename with spaces has to be
pre-encoded by the caller, because the gem will not invent an encoding it would then sign. A blob
filename with a space is ordinary. So: the mapping percent-encodes nothing and instead **omits
`dl:` and falls back** when the filename would not survive, rather than raising inside a route
helper on a page that was working yesterday. This is the one place the slice tolerates a
silently-degraded result, and it is called out here so it is a decision rather than a discovery.

`disposition: :inline` maps to nothing — it is the proxy's default behaviour — and every other
ActiveStorage URL option (`expires_in:`, `filename:`) is dropped, since the proxy's URLs carry their
own expiry model (none) and their own filename option (`dl:`).

### D6 — Audio stays invariable, and the gem never widens `variable_content_types` **[Amended]**

Superseded by D1's cut. What was a mitigation is now a boundary: the gem does not make audio
variable, does not register a transformer or a previewer, and leaves `InvariableError` and
`UnrepresentableError` to fire as Rails intends.

The interception layer this decision used to describe — raising from `#processed`, `#process`,
`#download` and `#image` on an audio variant, so nothing hands an mp3 to vips — is no longer needed,
because there is no audio variant to hold. That deletion is the clearest measure of what the cut
bought.

Per-variant proxy options remain fully expressible: `audioproxy_url(recording.audio, format: "opus",
bitrate: 96)`. The gem already has that vocabulary; Rung B would only have added a second, worse
spelling of it that had to be smuggled through a hash Rails validates for other purposes.

### D7 — Withdrawn **[Amended]**

Specified the `variant(audioproxy: {…})` transformation key and its rejection rules. Withdrawn with
Rung B (D1). Recorded rather than deleted so the archived design shows what was considered.

## Upstream: what it would take to do this properly

Researched at the user's request, against `rails/rails` and the installed Rails 8.1.3.1. This is the
"explore ways to add it to Rails" half of the answer, and it is recorded here so the next person to
ask about `blob.representation` finds the landscape instead of re-deriving it.

**The PR that would fix this is [#39283](https://github.com/rails/rails/pull/39283), "ActiveStorage
enable variants for custom media types."** It proposed exactly the missing piece: a registration
system for custom transformers, keyed by content type, mirroring how previewers already work — plus
an example ffmpeg transformer. Its history is more encouraging than its state suggests:

- Opened May 2020. George Claghorn: "Waiting to review this until after 6.1 ships."
- Auto-closed as stale in May 2022, then **reopened by a maintainer (guilleiguaran) in June 2023**.
- Still being commented on as recently as December 2025.
- **Never rejected on merit.** No maintainer argued the feature was wrong; it died of review latency.

Two concrete technical blockers were raised, and both are worth knowing before reviving it:

1. **`VariantRecord` hardcodes `has_one_attached :image`**, and the default variant format assumes
   PNG. A non-image variant has nowhere correct to store its output.
2. **Previewable and variable are treated as mutually exclusive** by the `/representations/`
   routing, but a video (or audio) variant would be both, and the endpoint cannot tell which was
   asked for.

**The seam that already exists and is closest in shape is `ActiveStorage.previewers`** — a list, with
per-blob `accept?`, publicly documented as extensible, and consulted by `representation` *before*
`variable?`. It is the right registry shape. It is the wrong output type: a previewer produces an
*image* by downloading and processing the blob, and this proxy renders peaks as JSON or a binary
`.dat`, not a picture.

That points at a concrete path that does not go through Rails at all: **if the audioproxy server
gained a waveform-*image* format, this gem could register an ordinary `ActiveStorage::Previewer`**
and `blob.representation` would work through Rails' sanctioned path with no hacks, no
`variable_content_types` widening and no interception. That is a proposal for the parent project,
not for Rails, and it is the cheapest of the three routes to the feature originally asked for.

**What a #39283 revival would actually buy this gem is the predicate, not the processing.** Worth
stating precisely, because it narrows the ask. That PR generalizes the transformer *registry* to be
keyed by content type; the transformer contract stays `transform(file, format:) { |tempfile| }`, so
what it adds to Rails is local ffmpeg transcoding of audio — the very work this proxy exists to move
off the app server. But it also makes `blob.variable?` answer true for audio **truthfully**, because
a real transformer is registered for that content type, and that is the whole of what Rung B was
lying about.

With the predicate honest, this gem needs no interception layer at all: `resolve_model_to_route`
resolves `url_for(variant)` at URL-generation time, which is strictly ahead of `.processed`, so the
proxy serves the URL and the registered local transformer simply never runs. The local path stays
available as the development fallback — precisely the arrangement imgproxy-rails uses, vips in
development and imgproxy in production.

That also re-weights the two blockers for this consumer. The `/representations/` previewable-versus-
variable ambiguity would still bite. `VariantRecord`'s hardcoded `has_one_attached :image` largely
would not, since nothing here ever stores transformer output. A revival argued as "here is a gem
that needs the predicate, not the processing" is narrower, and easier to defend, than the original
PR's framing.

Ranked, then: (1) a waveform-image format in the proxy plus a previewer here; (2) reviving #39283
upstream, with the two blockers above named and the predicate-not-processing framing; (3) the
`variable_content_types` workaround, which is what this slice just cut.

## Risks / Trade-offs

- **[Opting in changes every ActiveStorage URL in the app]** → That is the feature, and it is also
  the risk. Mitigated by D3's fallback (non-audio is untouched), by D4's fallback (unsupported
  services are untouched), by the setting being per-environment so staging proves it before
  production, and by `rails_blob_url` remaining available per call site as the explicit opt-out.
- **[`routes.append` + `direct` may not compose as expected]** → D2. Verified by test, not by
  reasoning, including across a development route reload. If it does not hold, the decision is
  amended rather than the constraint quietly broken.
- **[Cutting Rung B leaves `recording.audio.variant(…)` raising]** → It raises today and would have
  gone on raising for every app that did not opt into a global `variable_content_types` widening.
  `audioproxy_url(recording.audio, format: "opus")` expresses the same thing with no pretending.
  The three upstream routes to a real fix are ranked above.
- **[D5 silently omits `dl:` for an awkward filename]** → A download that arrives with the proxy's
  default filename instead of the blob's. Visible, harmless, and preferable to a 500 in a route
  helper. Logged at debug.
- **[The dummy app can only be configured one way at boot]** → `resolve_model_to_route` is read at
  app configuration time, so the opted-in and default behaviours cannot both be exercised in one
  booted app. Needs either a second dummy environment or a test that manipulates the route set
  directly; the former is more honest and is what Tasks assumes.
- **[Divergence from imgproxy-rails' conventions]** → An app running both gems gets
  `imgproxy_options:` for images and `audioproxy:` for audio, and two different fallback defaults.
  Accepted: matching a sibling gem's spelling is worth less than each gem's key being right for its
  own vocabulary, and the fallback difference is a deliberate correction (D3).

## Open Questions

- ~~Should Rung B ship at all?~~ **Answered: no.** Cut before implementation; see D1, D6, D7 and
  the upstream section. The follow-ups it generates are the two below.
- Should the proxy gain a waveform-*image* format? It is the cheapest route to a real
  `blob.representation` for audio, because it makes an ordinary `ActiveStorage::Previewer` viable
  and previewers are already a supported extension point. Belongs on the parent project's tracker,
  alongside the `norm`/`gain`-for-peaks question from `add-info-and-peaks-urls` D6.
- Is reviving rails/rails#39283 worth the effort? It was never rejected on merit and a maintainer
  reopened it once already. Its two blockers (`VariantRecord`'s hardcoded `has_one_attached :image`,
  and previewable-vs-variable ambiguity in `/representations/` routing) are the price of entry.
  Decide after this gem has real users, since "an audio gem wants this" is a stronger revival
  argument with a gem behind it.
- Should the audio content-type check consult the *proxy's* view instead — that is, attempt the URL
  and let the proxy's `415 video_source` gate decide? No: that is a network round trip per URL
  generated, and URL building is synchronous in a view. Content type is the only local signal.
  Recorded so it is not re-proposed.
- Does an app want per-model rather than per-app opt-in (`has_one_attached :audio, proxy: true`)?
  That would be a different mechanism entirely — not `resolve_model_to_route` — and is worth a
  separate proposal if the app-wide switch proves too blunt.
