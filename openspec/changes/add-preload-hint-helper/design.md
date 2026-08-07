## Context

`Audioproxy::Rails::Helpers` currently holds two methods: `audioproxy_url` (a rename of
`Audioproxy.url_for`) and `audioproxy_audio_tag` (that URL handed to ActionView's `audio_tag`, with
tag attributes segregated into an `html:` bucket per `add-rails-integration` D4). This slice adds a
third in the same shape, over ActionView's `preload_link_tag`.

Two properties of the proxy make an audio preload behave unlike a static-asset preload, and both
come from the API doc (`../audioproxy/docs/audio-proxy-api-v1.md` §5):

- **On a cache MISS** the response is `200` with `Transfer-Encoding: chunked`, no `Content-Length`
  and **no `Accept-Ranges`**. There is no partial fetch to be had: a preload of a cold variant
  downloads the entire render as it is produced.
- **On a HIT** the default serve mode answers `302` to a presigned URL with
  `Cache-Control: no-store` on the redirect itself. A preload follows the redirect and caches the
  variant under the presigned URL, whose `Location` expires after `AP_PRESIGN_TTL`.

Neither stops the hint from working. Both are why the README has to say what this hint costs, rather
than presenting it as free.

The relevant ActionView behaviour: `preload_link_tag(source, options)` resolves `as` from the
source's extension via `resolve_link_as`, and — when `config.action_view.preload_links_header` is
on — also appends the URL to the response's `Link` header.

## Goals / Non-Goals

**Goals:**

- One helper that cannot drift from the `<audio>` element it accompanies, because both take the same
  source and options and run them through the same builder.
- A correct `as` on every emitted tag.
- Documented caveats that are specific to preloading a *rendered* resource.

**Non-Goals:**

- `preconnect`/`dns-prefetch` helpers for the proxy origin. Genuinely useful for a cross-origin
  proxy and nearly free, but they take no source and no options — they are one hand-written
  `<link rel="preconnect" href="…">` against a host the app already has in config, and a helper
  would only be wrapping a string. See Open Questions.
- Emitting the hint automatically from `audioproxy_audio_tag`. A hint belongs in the head, the tag
  belongs in the body, and a helper that silently emitted markup in two places would be a surprise —
  and wrong on any page with more than a couple of tracks.
- `<link rel="prefetch">` (next-navigation priority) as a second helper. Same tag, one attribute
  different; if it is wanted, it is an option on this helper, not a sibling.
- Deciding *whether* a given page should preload. That is the app's judgment about its own traffic.

## Decisions

### D1 — Delegate to ActionView's `preload_link_tag` rather than building the `<link>`

Same reasoning as `add-rails-integration` D4 for `audio_tag`: Rails owns tag construction, attribute
escaping and boolean-attribute rendering, and it also owns the `Link`-header side effect that
`config.action_view.preload_links_header` turns on. Hand-building the tag would silently drop that
integration and would need re-checking against every Rails release.

The cost is that this helper inherits `preload_link_tag`'s behaviour wholesale, including the header
emission. That is stated in the README rather than suppressed: an app that does not want the `Link`
header turns off the Rails setting that produces it, in one place, for all preloads.

### D2 — `as: "audio"` is the default, and the reason is structural

`preload_link_tag` infers `as` from the source's extension. A proxy URL ends in
`enc/{unpadded base64url}` — no extension, by construction, since the source is encoded precisely so
its own spelling cannot leak into the path. So the inference always fails here and always would.

`rel=preload` without `as` has no fetch destination: browsers warn and decline to preload, and the
tag becomes a no-op that looks like it is working. Supplying `as: "audio"` in the helper rather than
asking every call site for it is the difference between a helper and a reminder.

`html: { as: "video" }` overrides it, for a caller who knows better.

### D3 — `crossorigin` is not set, and this is a deliberate default rather than an oversight

A preload and the element that consumes it must agree on `crossorigin`, or the browser treats them
as two different requests and downloads the resource twice — the classic preload footgun, and a
costly one when the resource is a whole audio render rather than a font.

`audioproxy_audio_tag` sets no `crossorigin` unless the caller puts one in `html:`. So the matching
default here is also nothing. A caller who adds `crossorigin` to the audio element must add the same
value here, and the README says so next to both helpers.

Rejected: defaulting to `crossorigin: "anonymous"` because the proxy is usually a different origin.
It is the right value only for callers who also set it on the element, and it silently doubles
bandwidth for everyone else.

### D4 — The `html:` bucket, unchanged

`audioproxy_preload_link_tag(source, html: {}, **options)`, identical in shape to
`audioproxy_audio_tag`, including the `ArgumentError` when `html:` is not a Hash. Proxy options
never reach the `<link>`; link attributes never reach the proxy. The argument from
`add-rails-integration` D4 applies verbatim — without the bucket, a typoed `bitrat: 96` would land
on the element as an attribute and quietly preload the default format, which is the exact
double-download this helper is supposed to avoid.

### D5 — Verify that ActionView does not rewrite the URL

`preload_link_tag` runs its source through `path_to_asset`, which is asset-pipeline machinery. For
an absolute `http(s)` URL it should return the string untouched, but "should" is the wrong standard
for a gem whose failure mode is a 403 far from the call site: a mangled path is a bad signature.
This gets an explicit test asserting the emitted `href` is byte-identical to `audioproxy_url` for
the same arguments, including for an endpoint carrying a path prefix. The same assertion is worth
having for `audio_tag`, which has never had it.

## Risks / Trade-offs

- **[A preload downloads the entire variant]** → Real, and unavoidable: §5 gives a MISS no
  `Accept-Ranges`, so there is no range for the browser to stop at. Mitigated by documentation
  rather than code — the helper is correct, the judgment about whether to use it on a given page is
  the app's. The README states it in the same paragraph that introduces the helper, not in a footnote.
- **[Options drift between the hint and the element]** → The failure this slice exists to prevent,
  and it is only prevented if callers pass the same options to both. A helper cannot enforce that
  across two call sites in two templates. The README's example shows both together with a shared
  local, which is the shape that makes drift visible.
- **[`crossorigin` mismatch doubles the download]** → D3 picks the default that matches the sibling
  helper's, and the README documents the pairing. Nothing else is available: the helper cannot see
  the element.
- **[`Link` header growth]** → `preload_links_header` emits a header per preload, and a page listing
  fifty tracks that preloads each would produce a header some proxies truncate or reject. Worth a
  README sentence: preload the track that is about to play, not the list.

## Open Questions

- Is a `preconnect` helper wanted after all? It is one line of markup, but it is the hint with the
  best cost/benefit ratio for a cross-origin proxy, and unlike preload it is safe to emit on every
  page. It would be the first helper in this gem that takes a config value and no source. Decide
  after this slice ships, on whether the README's hand-written example feels like a gap.
- Should the README's preload example use `fetchpriority`? It is well supported and it is the
  attribute that makes "preload this one track, not the list" expressible. Leaning yes, as an
  example rather than a default.
