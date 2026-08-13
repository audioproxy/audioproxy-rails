# Add Expiring URLs (`expires_in:` / `expires_at:`)

## Why

The proxy is gaining expiring URLs (`add-expiring-urls` in the audioproxy repo, in implementation now): an `exp:<unix-seconds>` option in the signed path, verified after the signature and answered with 410 once past. It is a *request option* on the proxy side — signed but excluded from the cache key — so every user can carry their own short-lived URL while all of them share one cached variant.

That design is only ergonomic if the gem does the arithmetic. Nobody wants to compute unix timestamps in a view; the Rails-native spelling is `expires_in: 1.hour`. This is also what makes per-request URL rotation free: each page render mints a fresh short-lived URL, and the proxy's cache-key exclusion means none of that rotation costs a render.

## What Changes

- `url_for` (and therefore every view helper that forwards to it) accepts two new keywords, mutually exclusive:
  - `expires_in:` — an ActiveSupport duration or positive Integer seconds, added to the current time at build time.
  - `expires_at:` — a `Time`/`DateTime`/`ActiveSupport::TimeWithZone` or Integer unix timestamp, used as-is.
- Either renders an `exp:<unix-seconds>` segment through the ordinary options pipeline (integer, never decimal). The proxy normalizes option order, so placement is not load-bearing.
- **Fail loudly at call time**, per the house rule that a wrong byte 403s (now 410s) far from the call site: both keywords given raises; a non-positive `expires_in` raises; an `expires_at` at or before now raises (minting an already-dead URL is a programmer error, not a request). A typo'd type raises rather than coercing.
- Optional global default: `config.expires_in` (nil by default — URLs stay eternal unless asked). A per-call `expires_in:`/`expires_at:` overrides it; per-call `expires_in: nil` opts a single URL out of a global default.
- `Signer` is untouched. `exp` is ordinary path bytes to it; the extraction seam and the isolation test stand exactly as they are.
- README: the two keywords, the global default, the rotation-for-free story, and the minimum proxy version.

## Coupling and sequencing

Hard dependency on the **proxy release** that ships `exp`: an older proxy answers `exp:` with 400 invalid-option, so this gem feature is useless (though harmless — the URL fails loudly server-side) against it. The README states the minimum proxy version; the gem does not version-sniff. Implement once the proxy change is merged and its release is tagged, so the round-trip test below can run against a real container.

If the proxy's published signature vectors gain an `exp`-bearing vector, copy it into `test/fixtures/signature_vectors.rb`; never regenerate vectors from this gem's own signer.

## Capabilities

### New Capabilities

<!-- none -->

### Modified Capabilities

- `options-rendering`: `exp` as a renderable option with integer-seconds semantics.
- `url-building`: the two keywords, their validation, the build-time clock.
- `view-helpers`: pass-through of both keywords.
- `configuration`: optional `expires_in` default, nil meaning no expiry.

## Impact

- Modified: `Audioproxy::Options` (render `exp`), `Audioproxy::UrlBuilder` (keyword handling + validation + clock), `Audioproxy::Config` (default), view helpers (forwarding), README, CHANGELOG.
- Tests: unit tests for arithmetic, mutual exclusion, and every raise path; a rendering test that `expires_in: 90` from a frozen clock yields the exact `exp:` segment; helper forwarding; and one `:server`-tagged round-trip against a proxy container new enough to verify (renders before expiry, 410 after).
- Estimated ~150 LOC including tests.
- Position: next up in this repo, gated on the proxy release. `add-info-and-peaks-urls` and `add-representation-hook` are independent and unaffected.
