## 1. Info URL

- [x] 1.1 Add `UrlBuilder#info_url(source, endpoint: nil, unsigned: nil)` building `/info/{source-segment}` with no options segment, reusing the existing endpoint resolution, source segment builder and signing path (D1)
- [x] 1.2 Raise `ArgumentError` from `info_url` for `raw:` or any typed option key, naming the proxy's no-options rule and its `422` (D1)
- [x] 1.3 Ensure `config.default_options` is never consulted by `info_url`, typed or `raw:`, with a comment at the call site citing API v1 §4 (D2)
- [x] 1.4 Expose `Audioproxy.info_url` as a module-level entry point beside `url_for`
- [x] 1.5 Never apply `config.expires_in` to `info_url`; raise for a non-nil per-call `expires_in:`/`expires_at:`, accept an explicit `nil` (D9)

## 2. Peaks URL

- [x] 2.1 Add the peaks option allowlist (`pts`, `pk_fmt`, `ch`, `t`, `fade`, `gain`, `norm`, `dl`, `cb`) to `Audioproxy::Options`, next to the existing key table and citing API v1 §3.3 (D4, D6)
- [x] 2.2 Add `UrlBuilder#peaks_url(source, **options)` that resolves aliases, screens against the allowlist, seeds `f: :peaks`, and delegates to the existing rendering path (D3)
- [x] 2.3 Raise `ArgumentError` for a conflicting explicit format, in the register of the existing "given twice" error; accept a redundant `format: :peaks` (D3)
- [x] 2.4 Confirm no channel default is materialized when `ch` is absent (D5)
- [x] 2.5 Expose `Audioproxy.peaks_url` as a module-level entry point
- [x] 2.6 If `add-peaks-bit-depth` has already landed in this gem, add `pk_bits` to the allowlist and test `peaks_url(src, pk_bits: 8)`. If not, that change adds it (D6)
- [x] 2.7 If `add-enhance-key` has already landed in this gem, add `enhance` to the allowlist and test `peaks_url(src, enhance: :voice)`. If not, that change adds it (D6). *Not landed; `add-enhance-key` carries it.*
- [x] 2.8 Apply only allowlisted typed defaults to `peaks_url`, skip the rest and any `raw:` default; reject a per-call `raw:`; always render `f:peaks` first; let expiry apply as on `url_for` (D3 amended, D10)

## 3. View helpers

- [x] 3.1 Add `audioproxy_info_url` and `audioproxy_peaks_url` to `Audioproxy::Rails::Helpers` as thin delegations (D7)
- [x] 3.2 No tag helper for either; record the reason in a comment so it is not added later by reflex (D7)

## 4. Tests

- [x] 4.1 Info URL shape: no options segment, `enc/` source, endpoint prefix, trailing-slash normalization
- [x] 4.2 Info signing against known-answer vector 2 (`/info/plain/s3://b/k.wav`), through the builder's signing path rather than `Signer` alone (D8)
- [x] 4.3 Info rejects `raw:` and every typed key; info ignores both typed and `raw:` defaults (D2) — assert the *absence* of the default's segments, not merely that a URL was produced
- [x] 4.4 Info honours `endpoint:` and `unsigned:` overrides, including the `insecure` segment with no key or salt configured (Open Question 2)
- [x] 4.5 Peaks: minimal URL, options render, allowlist rejection for each excluded key, conflicting format rejection, redundant format accepted, no `ch:1` materialization
- [x] 4.6 Blob and attachment sources through both new entry points, proving they share the resolver hook
- [x] 4.7 Regression: assert an existing `url_for` URL is byte-identical before and after this slice

## 5. Docs

- [x] 5.1 README: an `info` and peaks section under Generating URLs, covering the no-options rule, the defaults asymmetry (D2), the peaks allowlist and why it exists (D4), and the `max-age=3600`-not-`immutable` caching note for info responses
- [x] 5.2 README Status paragraph: name the two new URL shapes
- [ ] 5.3 Replace the placeholder Purpose in `openspec/specs/url-building/spec.md` ("TBD - created by archiving change add-gem-core-signing") as part of the archive step
- [x] 5.4 Check the allowlist against the proxy's API v1 §3.3 once more before merge. The `norm`/`gain` question is answered: the proxy respects both for peaks (D6). *Rechecked against proxy v0.8.0: §3.3 and `@peaks_unsupported ~w(br q sr bd)` agree with the allowlist.*

## 6. Gates

- [x] 6.1 `bin/test` green
- [x] 6.2 `bin/rubocop` green
- [x] 6.3 `openspec validate add-info-and-peaks-urls` passes
- [ ] 6.4 Outside code review per CLAUDE.md, ordered by failure mode: byte-correctness of the info path first, then inputs that produce a plausible-but-wrong URL
