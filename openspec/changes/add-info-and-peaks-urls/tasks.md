## 1. Info URL

- [ ] 1.1 Add `UrlBuilder#info_url(source, endpoint: nil, unsigned: nil)` building `/info/{source-segment}` with no options segment, reusing the existing endpoint resolution, source segment builder and signing path (D1)
- [ ] 1.2 Raise `ArgumentError` from `info_url` for `raw:` or any typed option key, naming the proxy's no-options rule and its `422` (D1)
- [ ] 1.3 Ensure `config.default_options` is never consulted by `info_url`, typed or `raw:`, with a comment at the call site citing API v1 §4 (D2)
- [ ] 1.4 Expose `Audioproxy.info_url` as a module-level entry point beside `url_for`

## 2. Peaks URL

- [ ] 2.1 Add the peaks option allowlist (`pts`, `pk_fmt`, `ch`, `t`, `fade`, `dl`, `cb`) to `Audioproxy::Options`, next to the existing key table and citing API v1 §3.3 (D4, D6)
- [ ] 2.2 Add `UrlBuilder#peaks_url(source, **options)` that resolves aliases, screens against the allowlist, seeds `f: :peaks`, and delegates to the existing rendering path (D3)
- [ ] 2.3 Raise `ArgumentError` for a conflicting explicit format, in the register of the existing "given twice" error; accept a redundant `format: :peaks` (D3)
- [ ] 2.4 Confirm no channel default is materialized when `ch` is absent (D5)
- [ ] 2.5 Expose `Audioproxy.peaks_url` as a module-level entry point

## 3. View helpers

- [ ] 3.1 Add `audioproxy_info_url` and `audioproxy_peaks_url` to `Audioproxy::Rails::Helpers` as thin delegations (D7)
- [ ] 3.2 No tag helper for either; record the reason in a comment so it is not added later by reflex (D7)

## 4. Tests

- [ ] 4.1 Info URL shape: no options segment, `enc/` source, endpoint prefix, trailing-slash normalization
- [ ] 4.2 Info signing against known-answer vector 2 (`/info/plain/s3://b/k.wav`), through the builder's signing path rather than `Signer` alone (D8)
- [ ] 4.3 Info rejects `raw:` and every typed key; info ignores both typed and `raw:` defaults (D2) — assert the *absence* of the default's segments, not merely that a URL was produced
- [ ] 4.4 Info honours `endpoint:` and `unsigned:` overrides, including the `insecure` segment with no key or salt configured (Open Question 2)
- [ ] 4.5 Peaks: minimal URL, options render, allowlist rejection for each excluded key, conflicting format rejection, redundant format accepted, no `ch:1` materialization
- [ ] 4.6 Blob and attachment sources through both new entry points, proving they share the resolver hook
- [ ] 4.7 Regression: assert an existing `url_for` URL is byte-identical before and after this slice

## 5. Docs

- [ ] 5.1 README: an `info` and peaks section under Generating URLs, covering the no-options rule, the defaults asymmetry (D2), the peaks allowlist and why it exists (D4), and the `max-age=3600`-not-`immutable` caching note for info responses
- [ ] 5.2 README Status paragraph: name the two new URL shapes
- [ ] 5.3 Replace the placeholder Purpose in `openspec/specs/url-building/spec.md` ("TBD - created by archiving change add-gem-core-signing") as part of the archive step
- [ ] 5.4 Raise the `norm`/`gain`-for-peaks question on the proxy's issue tracker (D6, Open Questions)

## 6. Gates

- [ ] 6.1 `bin/test` green
- [ ] 6.2 `bin/rubocop` green
- [ ] 6.3 `openspec validate add-info-and-peaks-urls` passes
- [ ] 6.4 Outside code review per CLAUDE.md, ordered by failure mode: byte-correctness of the info path first, then inputs that produce a plausible-but-wrong URL
