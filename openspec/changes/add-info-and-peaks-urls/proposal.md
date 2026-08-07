## Why

The proxy answers three signed URL shapes; this gem builds one of them. `GET /{sig}/{options}/{source}`
is the rendered variant, and that is all `url_for` knows how to assemble. The other two are what an
audio UI actually needs before and around playback:

- `GET /{sig}/info/{source}` returns `ffprobe` metadata as JSON — duration, sample rate, channels,
  bit depth, tags. A player asks for it *before* it knows what variant to request, and it is how a
  caller learns the duration it needs in order to write a sensible `t:` in the first place.
- `f:peaks` returns waveform min/max pairs for drawing a waveform.

Peaks are reachable today by hand (`url_for(source, f: :peaks, pts: 800)`), but nothing stops
encoding options riding along into a URL where the proxy ignores them and the cache key does not.
`info` is not reachable at all, and not by oversight: its grammar has **no options segment**, and
`UrlBuilder#url_for` structurally always emits one — with `f:mp3` as the floor when it has nothing
else to say. An `/info` URL carrying an options segment is a `422` at the proxy (API v1 §4).

Both were named as deferred non-goals in `add-gem-core-signing` and again in `add-rails-integration`.
The behaviour they build on — signing, source encoding, option rendering, blob resolution — has all
shipped, so they are now purely additive.

## What Changes

- **New `Audioproxy.info_url(source, endpoint: nil, unsigned: nil)`** producing
  `{endpoint}/{signature}/info/{source-segment}`. It accepts no proxy options at all — not `raw:`,
  not typed keys — and raises `ArgumentError` naming the `422` if given any.
- **Configured `default_options` deliberately do not apply to `info_url`.** Every other entry point
  honours them; this one cannot, because any options segment alongside `info` is rejected by the
  proxy. Stated as a requirement so it can never be "fixed" into a 422 generator.
- **New `Audioproxy.peaks_url(source, **options)`**, which is `url_for` with `f:peaks` fixed. It
  accepts only the options the proxy documents as meaningful for peaks (`pts`, `pk_fmt`, `ch`, `t`,
  `fade`, `dl`, `cb`) and raises on the rest, rather than emitting a URL whose extra segments change
  the cache key without changing a single returned byte.
- **New view helpers `audioproxy_info_url` and `audioproxy_peaks_url`**, thin delegations matching
  `audioproxy_url`. No tag helper: peaks are JSON or binary a script fetches, and `info` is JSON —
  neither has an HTML element to be handed to.
- Source resolution is unchanged and shared: blobs, attachments and `has_one_attached` work as
  sources for both new entry points, because both go through the same source segment builder.
- README gains an `info` and peaks section.

## Capabilities

### New Capabilities

None. Both are additional shapes of the URL this gem already builds, and splitting them into their
own capabilities would separate `/info`'s signing from `url-signing` and its source encoding from
`url-building` for no gain.

### Modified Capabilities

- `url-building`: adds the `info` URL shape (no options segment, defaults not applied, options
  rejected) and the peaks URL shape (`f:peaks` fixed, option allowlist). Also fills in the spec's
  placeholder Purpose, which has read "TBD - created by archiving change add-gem-core-signing" since
  that change was archived.
- `view-helpers`: adds `audioproxy_info_url` and `audioproxy_peaks_url`.

## Impact

- `lib/audioproxy.rb` — two new module-level entry points beside `url_for`.
- `lib/audioproxy/url_builder.rb` — an `info_url` path that bypasses the options segment entirely,
  and a `peaks_url` path that fixes `f:` and screens the rest. The existing `url_for` is untouched;
  if this slice changes a single variant URL, it is wrong.
- `lib/audioproxy/options.rb` — the peaks option allowlist, next to the existing key table.
- `lib/audioproxy/rails/helpers.rb` — two delegations.
- `README.md` — a new section under Generating URLs.
- No new dependencies. No change to `Audioproxy::Signer`, which already signs an arbitrary path and
  is proven against the `/info/plain/s3://b/k.wav` known-answer vector this slice finally exercises
  end to end.
