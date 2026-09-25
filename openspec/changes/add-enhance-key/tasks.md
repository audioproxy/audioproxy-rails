## 1. Options

- [ ] 1.1 Add `enhance` to `Audioproxy::Options::KEYS`
- [ ] 1.2 Add `enhance: :enhance` to `ALIASES`, like `fade` and `gain`
- [ ] 1.3 Test that `enhance: :voice` renders `enhance:voice`, and that an unknown preset renders rather than raising
- [ ] 1.4 If `add-info-and-peaks-urls` has already landed, add `enhance` to the `peaks_url` allowlist and test `peaks_url(src, enhance: :voice)`. If not, that change adds it (its D6)

## 2. Documentation

- [ ] 2.1 Add the `enhance` row to the README's option table
- [ ] 2.2 Add a line to the README's "Minimum proxy version" section: `enhance` needs proxy 0.7.0

## 3. Archive

- [ ] 3.1 If `add-peaks-bit-depth` archived first, add `pk_bits:` and `peak_bits`→`pk_bits` to this change's delta before archiving, so the main spec keeps both keys
