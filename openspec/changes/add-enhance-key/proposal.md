## Why

The proxy has an `enhance` option since 0.7.0. It takes a preset name, today only `voice`, and applies a pinned filter chain before every other stage. The gem does not know the key, so `url_for(source, enhance: :voice)` raises. A Rails caller can reach the option only through `raw:`, which gives up the typed path and the alias table.

The gap also blocks `peaks_url`. The proxy respects `enhance` for peaks, so the waveform matches the enhanced audio. `add-info-and-peaks-urls` D6 keeps `enhance` out of the peaks allowlist until the gem has the key.

## What Changes

- Add `enhance` to the recognized option keys, rendered as `enhance:<preset>` like every other typed key.
- `enhance` is already a word, so it is its own alias, like `fade` and `gain`.
- No value validation. `enhance: :music` renders, and the proxy answers `422`, as for every other out-of-domain value.
- Add `enhance` to the `peaks_url` allowlist if `add-info-and-peaks-urls` has landed. If not, that change adds it (its D6).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `options-rendering`: one new key in the typed-key list and one new entry in the alias table.

## Impact

`Audioproxy::Options::KEYS` and `ALIASES`, the README's option table and its "Minimum proxy version" section (0.7.0), and the option tests that enumerate keys and aliases.

`add-peaks-bit-depth` modifies the same two requirements. Whichever of the two changes archives second must carry both keys in its delta, or the archive drops the other key from the main spec.
