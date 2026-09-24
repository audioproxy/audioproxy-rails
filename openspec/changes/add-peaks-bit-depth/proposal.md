## Why

The proxy is gaining `pk_bits`, a peaks-scoped option taking `8` or `16`, so that `f:peaks` output can be loaded directly by peaks.js — which refuses waveform data that is not 8-bit. Until the key exists here, a Rails caller cannot reach it: `url_for` raises on an unknown key, which is the correct failure but also a hard stop.

This is the companion to `add-peaks-bit-depth` in the proxy repo, and it cannot ship before it: a URL carrying `pk_bits` would be refused by any proxy that does not yet parse it.

## What Changes

- Add `pk_bits` to the recognized option keys, rendered as a `key:value` segment like every other typed key.
- Add `peak_bits` as its spelled-out alias, following `peak_count`→`pts` and `peak_format`→`pk_fmt`.
- No value validation. `pk_bits: 24` renders and the proxy answers `422`, exactly as `br: 999999` does today.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `options-rendering`: one new key in the typed-key list and one new entry in the alias table.

## Impact

`Audioproxy::Options::KEYS` and `ALIASES`, the README's option table, and the two option tests that enumerate keys and aliases.

No version constraint on the proxy is expressed or enforced — the gem has never modelled one, and the failure mode is a `422` from a proxy that is too old, which is legible on its own. The README's "Minimum proxy version" section is where that expectation is recorded, and it gains a line.
