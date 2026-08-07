## Why

`audioproxy_audio_tag` puts a proxy URL on an `<audio>` element, and that is the point at which the
browser starts thinking about the bytes. For a page where playback is likely — a track page, a
player that opens on load — a resource hint in the document head starts the fetch earlier, and for a
proxy URL it does something an ordinary asset preload does not: it warms the *variant cache*. The
first request for a variant is a render, so the hint converts a user-visible render wait into one
that overlaps page load.

Writing the hint by hand means writing `audioproxy_url` twice — once in the head, once in the tag —
and keeping the option lists byte-identical, because a single differing option is a different
variant, a different cache key, and a preload the browser never matches to the element that needs
it. That is the failure this gem exists to prevent, moved from the URL into the page.

`add-rails-integration` deferred a preload-hint helper as "later, additive". The helper it needs
(`audioproxy_url`) and the `html:` bucket convention both shipped in that slice.

## What Changes

- **New view helper `audioproxy_preload_link_tag(source, html: {}, **options)`** that builds the URL
  via `audioproxy_url` and delegates to Rails' own `preload_link_tag`, producing
  `<link rel="preload" as="audio" href="…">`.
- **`as: "audio"` is supplied by default**, because Rails infers `as` from the file extension and a
  proxy URL ends in an unpadded base64url payload with no extension. Without it the tag is a
  `rel=preload` with no destination, which browsers decline to act on.
- **`crossorigin` is not set by default**, and the README says why: a preload whose `crossorigin`
  does not match the element that consumes it downloads the resource twice. The default matches what
  `audioproxy_audio_tag` emits, which is nothing.
- The `html:` bucket carries any link attributes (`crossorigin`, `fetchpriority`, `type`, `media`),
  keeping the same seam `audioproxy_audio_tag` uses, so proxy options and tag attributes never share
  a namespace.
- README gains a preload section, including the two caveats that make this hint different from
  preloading a static asset: it fetches the *whole* variant, and on a cache MISS the proxy answers
  chunked with no `Accept-Ranges`, so there is no partial preload to be had.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `view-helpers`: adds `audioproxy_preload_link_tag`, its `as: "audio"` default, and the rule that
  proxy options never reach the emitted `<link>`.

## Impact

- `lib/audioproxy/rails/helpers.rb` — one helper, built on the two conventions already there.
- `README.md` — a preload subsection under View helpers.
- No change to `Audioproxy.url_for`, the builder, the signer or the core. This slice is
  ActionView-only: nothing outside `Audioproxy::Rails` is touched, and the gem's Rails-free half is
  not involved at all.
- No new dependencies. `preload_link_tag` is ActionView's, and ActionView is already how the
  existing helpers reach `audio_tag`.
