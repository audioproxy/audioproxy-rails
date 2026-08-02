## 1. Number formatter

- [ ] 1.1 Implement `Audioproxy::Options.format_number`: integers verbatim, whole floats as integers, ≤3-decimal minimal rendering via an explicit decimal path (no exponent forms), trailing-zero trim, negative-zero collapse, `ArgumentError` on excess precision
- [ ] 1.2 Number-formatting test suite: `30.0→30`, `12.5`, `-2.50→-2.5`, `0.125`, `0.001` (no exponent), `-0.0→0`, `0.1234` raises, Integer/Rational/BigDecimal inputs, string passthrough

## 2. Option rendering

- [ ] 2.1 Implement the key table (all fourteen proxy keys) and per-key segment rendering; unknown keys raise `ArgumentError` listing known keys
- [ ] 2.2 Implement array handling for multi-part options (`t`, `fade`, `norm`): colon-join formatted elements, scalar auto-wrap, symbol elements via `to_s`
- [ ] 2.3 Preserve caller keyword order when joining segments with `/`
- [ ] 2.4 Tests: each key renders, arrays render (`t:[12.5,30]→t:12.5:30`, `norm:[:ebu,-16,-1.5,11]`), scalar forms, order preservation, opaque `dl`/`cb` verbatim, no domain validation (out-of-range values render)

## 3. Builder integration

- [ ] 3.1 Wire typed keys into `UrlBuilder`/`url_for` alongside `raw:`; raise `ArgumentError` when both are given
- [ ] 3.2 Implement `default_options` merge semantics: typed per-call keys win key-by-key; per-call `raw:` replaces defaults; no options at all still falls back to `f:mp3`
- [ ] 3.3 End-to-end tests: typed options through to a signed URL (signature recomputed over the rendered options segment), raw/typed conflict, defaults merge

## 4. Documentation

- [ ] 4.1 README: typed options section — table of all fourteen keys with an example value each, array forms for `t`/`fade`/`norm`, the number-formatting rules and the "one variant, two spellings, two cache keys" rationale, the strict-precision error with the round-explicitly-at-the-call-site recommendation, `raw:` as escape hatch and its mutual exclusion with typed keys, `default_options` merge semantics
