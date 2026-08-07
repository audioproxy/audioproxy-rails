## Context

The proxy's API v1 (`../audioproxy/docs/audio-proxy-api-v1.md`) defines three signed URL shapes. §2
lists them:

| Endpoint | Purpose |
|---|---|
| `GET /{sig}/{options}/{source}` | Rendered audio variant |
| `GET /{sig}/info/{source}` | Probe metadata as JSON (no processing options) |
| `GET /{sig}/f:peaks/…/{source}` | Waveform peaks (a *format*, not a separate resource) |

That table settles the shape of this slice, and corrects the way both earlier changes named it.
`add-gem-core-signing` and `add-rails-integration` deferred "`info`/peaks URL helpers" as if they
were two endpoints. They are not: **`info` is an endpoint; peaks is a format.** The two need
different treatment, and conflating them would have produced a `peaks_url` that invented a path
segment the proxy does not route.

Two facts from the API doc drive every decision below:

- **`info` takes no options.** §4: "`info` takes **no** processing options: any option segment
  alongside it is a `422`." The signature covers `/info/{source}` and nothing else.
- **Peaks respect `t`, `ch` and `fade`, ignore encoding options** (§3.3), and take `pts` (default
  800) and `pk_fmt` (`json`|`dat`, default `json`). `ch` defaults to **1** for peaks, unlike every
  other format, and that default "is materialized into the cache key" by the proxy.

The known-answer vectors already carry `/info/plain/s3://b/k.wav` → `U6nyFdkSvjNo2mlBbJMGk1nwISbdcnEGlgKSWKBfKT4`.
`Audioproxy::Signer` has been proven against it since `add-gem-core-signing`, but nothing in the gem
has ever *built* a path of that shape. This slice is the first caller.

`UrlBuilder#url_for` cannot be that caller. It always emits an options segment — `FALLBACK_OPTIONS`
(`f:mp3`) is the floor when there is no `raw:`, no typed key and no default — precisely because the
variant grammar has no optionless form. The `info` grammar is the one place where an options segment
is the error.

## Goals / Non-Goals

**Goals:**

- `Audioproxy.info_url(source)` producing `{endpoint}/{sig}/info/{source-segment}`, byte-correct
  against the existing known-answer vector.
- `Audioproxy.peaks_url(source, **opts)` as `url_for` with `f:peaks` fixed and an option allowlist.
- View helpers for both, matching the existing `audioproxy_url` shape.
- Blobs and attachments work as sources for both, for free, via the existing resolver hook.
- Zero change to any URL `url_for` emits today.

**Non-Goals:**

- Fetching or parsing the `info` response. This gem builds URLs; it does not make HTTP requests, and
  an `info` client would drag in an HTTP library, a cache and an error taxonomy for the proxy's
  `415`/`504` rows. If that is ever wanted it is its own slice with its own dependency argument.
- Modelling the `info` JSON body (§4's `format`/`duration`/`bit_depth`… object) as a Ruby struct.
  Same reason: nothing here ever sees a response.
- A `<track>`/waveform tag helper. Peaks are `application/json` or `application/octet-stream` fetched
  by a script; there is no element to build.
- Validating `pk_fmt` or `pts` value domains. The proxy owns validation (`add-options-rendering` D1),
  and `pk_fmt: :jsn` is a `422` with a structured body, not a silent wrong answer.
- HLS (`/hls/…`, reserved for v2 per §2), `/health` and `/metrics` — the last two are unsigned and
  need no builder.

## Decisions

### D1 — `info_url` is its own method, not `raw: "info"`

`url_for(source, raw: "info")` already produces a byte-correct info URL today: `raw_segment` passes
the string through verbatim and the path becomes `/info/enc/…`. That accident is not a reason to
skip this slice; it is the reason the slice has to be explicit.

`raw:` means "here is a pre-rendered options string". Spelling `info` as an option string is a lie
about the grammar, and it inherits the whole `raw:` machinery: it composes with `default_options`
(D2), it is silently accepted alongside a `default_options` typed hash, and `raw: "info/f:opus"`
would render a 422 the caller cannot see coming. A method that *cannot* take options is the shape
that fails at the call site.

Alternatives rejected:

- **`url_for(source, info: true)`** — a builder flag among proxy options, in the one namespace where
  an unrecognized key raises. `info` is not an option and must not be spellable as one.
- **Document `raw: "info"` and add nothing.** Leaves `default_options` silently poisoning the URL
  and gives the caller no error for `raw: "info", br: 96`. Rejected on the repo's standing rule:
  never emit a plausible-but-wrong URL.

### D2 — `default_options` do not apply to `info_url`, and this is a requirement rather than an omission

An app that configures `default_options = { f: :opus, br: 96 }` — the configuration the README
recommends — would otherwise get `/{sig}/f:opus/br:96/info/…` or `/{sig}/info/…` depending on
implementation accident, and the first is a `422` on every info request in production.

So `info_url` never consults `config.default_options`. It is stated in the spec so a later reader
does not "fix" the inconsistency with every other entry point. The asymmetry is the proxy's, not
this gem's.

`endpoint:` and `unsigned:` overrides *do* apply: they are builder concerns, not proxy options, and
they are exactly as meaningful for an info URL as for a variant.

### D3 — `peaks_url` fixes `f:peaks` and rejects a conflicting explicit format

`peaks_url(source, f: :opus)` is incoherent. It raises, naming both, in the same register as the
existing "given twice, as bitrate and br" error from `add-option-aliases`. `f: :peaks` or
`format: :peaks` written explicitly is redundant but harmless, and is accepted.

`f:peaks` is placed in the same position the existing renderer would place it, so `peaks_url` is
literally `url_for` with a pre-seeded typed hash. This keeps one rendering path and one set of
number-formatting and value-escaping rules.

### D4 — `peaks_url` takes a positive allowlist of options, not a denylist

Accepted: `pts`, `pk_fmt`, `ch`, `t`, `fade`, `dl`, `cb` (and their spelled-out aliases). Everything
else raises, naming the accepted set.

The reasoning is the cache key, not correctness. §3.3 says peaks ignore encoding options — but §1
says options are "normalized before hashing into the cache key", and an ignored option is still in
the URL and therefore still in the key. `peaks_url(src, br: 96)` and `peaks_url(src)` return
byte-identical peaks from two cache entries, two CDN objects and two renders. And a caller who wrote
`br: 96` believed it did something.

A positive allowlist rather than a denylist of `br`/`q`/`sr`/`bd`: the list is then a direct
transcription of §3.3 sitting next to a citation of it, and a proxy option added later defaults to
rejected — a caller gets an error naming the accepted set — rather than defaulting to silently
cache-fragmenting.

This is the one decision in the slice that risks the drift `add-options-rendering` D1 warns about
(two rule sets, a stale client rejecting what a newer proxy accepts). It is accepted here because
the rule is not a *value* domain but a fixed structural fact about which options reach the peaks
renderer at all, and because the failure it prevents is invisible: a cache-fragmenting URL 200s.

Alternatives rejected:

- **Accept everything, document it.** The silent-cost failure mode this repo exists to prevent.
- **Strip the ignored options silently.** Worse: the gem would emit a URL the caller did not write,
  and `add-options-rendering` D3 already rules out client-side normalization.

### D5 — `ch` is not materialized client-side, even though peaks default it to 1

§3.3 says peaks default `ch` to 1 and the proxy materializes that default into the cache key. It is
therefore tempting to emit `ch:1` so the URL matches the key. Do not: `add-options-rendering` D3
settled that this gem renders what it was given, in the order given, and the proxy normalizes for
cache identity. Materializing one default here would be the half-normalization that invents a third
spelling, and it would be the only place in the gem that does it.

### D6 — Peaks ignore `gain` and `norm`, and the allowlist follows the doc rather than intuition

§3.3 lists `t`, `ch` and `fade` as respected. `gain` and `norm` are not listed, so D4's allowlist
excludes them and `peaks_url(src, gain: -2.5)` raises.

This is worth flagging upstream rather than working around here: a waveform drawn from an
un-normalized render will not match the amplitude of the `norm:`-normalized audio the player is
playing, which is a visible mismatch in exactly the UI peaks exist for. If the proxy later respects
`norm`/`gain` for peaks, this allowlist gains two entries and nothing else changes. See Open
Questions.

### D7 — Two view helpers, no tag helper

`audioproxy_info_url(source, **opts)` and `audioproxy_peaks_url(source, **opts)` delegate exactly as
`audioproxy_url` does. No `html:` bucket, because neither builds a tag: §4 returns JSON and §3.3
returns JSON or a binary `.dat`, both fetched by a script. Inventing a `<div data-peaks-url>`
convention would put this gem in the business of a JavaScript library's markup contract.

### D8 — The known-answer vector becomes a live assertion

`test/fixtures/signature_vectors.rb` vector 2 is `/info/plain/s3://b/k.wav`. Until now it only
proved `Signer` signs an arbitrary path. The new test asserts that `info_url` *builds* a path of
that shape, by signing `/info/plain/s3://b/k.wav` through the builder's own signing path and
comparing to the published signature. The emitted URL still uses `enc/` (the builder never emits
`plain/`), so the vector is exercised at the signer boundary, not by round-tripping the whole URL.

## Risks / Trade-offs

- **[D4's allowlist drifts from a future proxy]** → The list transcribes API v1 §3.3 and cites it in
  a comment. A proxy change that widens the peaks vocabulary makes this gem reject a valid option —
  loudly, at the call site, with a message naming what it accepts, which is a bug report rather than
  a silent wrong URL. Mitigated further by `raw:` on `url_for` remaining the escape hatch for
  anything the key table does not know: a caller can always fall back to
  `url_for(source, raw: "f:peaks/…")`.
- **[`info_url` skipping `default_options` surprises someone]** → It is the only entry point that
  ignores them, which is a genuine inconsistency. Mitigated by the spec requirement, a comment at
  the call site citing §4's 422, and a README sentence. The alternative — honouring them — is a
  guaranteed 422.
- **[Peaks URLs and variant URLs diverge in cache behaviour]** → Peaks participate in the cache key,
  write-back and HIT redirect exactly as audio variants do (§3.3, last line), so nothing special is
  needed here. Recorded because it was checked, not assumed.
- **[`info` responses are cacheable but mutable]** → §4.2: `max-age=3600`, deliberately not
  `immutable`, because the same URL answers differently after a re-upload. This gem emits no cache
  headers and this changes nothing in it, but it belongs in the README: an app that memoizes an info
  URL's *response* forever is holding a stale duration.

## Open Questions

- Should the proxy respect `norm` and `gain` for peaks (D6)? A waveform that does not match the
  normalized audio it accompanies is a UI defect. Raise on the proxy's tracker; this slice ships the
  doc-faithful allowlist either way and widens later if the answer is yes.
- Is `info_url` wanted in the `unsigned: true` development mode with a proxy running
  `AP_ALLOW_INSECURE`? It falls out for free from the shared builder path — no reason to special-case
  it — but it should get a test so it is deliberate rather than incidental.
