## 1. Options

- [ ] 1.1 Add `pk_bits` to `Audioproxy::Options::KEYS`
- [ ] 1.2 Add `pk_bits: :peak_bits` to `ALIASES`, and confirm `CANONICAL` inverts it without a collision against `bit_depth`
- [ ] 1.3 Test that `pk_bits: 8` and `peak_bits: 8` render `pk_bits:8` and produce identical URLs, signature included
- [ ] 1.4 Test that `bit_depth: 8` still renders `bd:8`, so the two peak-adjacent spellings cannot be confused
- [ ] 1.5 Test that an out-of-domain value renders rather than raising, per the no-client-side-validation requirement
- [ ] 1.6 If `add-info-and-peaks-urls` has already landed, add `pk_bits` to the `peaks_url` allowlist and test `peaks_url(src, pk_bits: 8)`. If not, that change adds it (its D6)

## 2. Documentation

- [ ] 2.1 Add the `pk_bits` / `peak_bits` row to the README's option table
- [ ] 2.2 Add a line to the README's "Minimum proxy version" section naming the proxy release that introduced the key
- [ ] 2.3 Mention in the README's peaks wording that `pk_bits: 8` is what peaks.js requires, since that is the reason the option exists

## 3. Release

- [ ] 3.1 Hold the release until the proxy change has shipped, so the gem cannot render a segment no deployed proxy accepts

## 4. Archive

- [ ] 4.1 If `add-enhance-key` archived first, add `enhance:` and `enhance`→`enhance` to this change's delta before archiving, so the main spec keeps both keys
