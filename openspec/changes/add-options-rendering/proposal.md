## Why

After `add-gem-core-signing`, the gem can only take a pre-rendered options string (`raw:`). Callers should write `Audioproxy.url_for(source, f: :opus, br: 96, t: [12.5, 30])` and get the proxy's canonical option grammar out — including the number-formatting rules the proxy's cache keys depend on. Getting a float rendered as `12.50` instead of `12.5` silently forks one variant into two cache keys; this is the "one variant, two spellings" trap in client form, and it is MVP-blocking.

## What Changes

- `Audioproxy.url_for` (and `UrlBuilder`) accepts the proxy's short option keys as Ruby keyword arguments: `f:`, `br:`, `q:`, `sr:`, `ch:`, `bd:`, `t:`, `fade:`, `gain:`, `norm:`, `pts:`, `pk_fmt:`, `dl:`, `cb:`.
- Multi-part options take arrays: `t: [12.5, 30]` → `t:12.5:30`, `fade: [1, 2]` → `fade:1:2`, `norm: [:ebu, -16, -1.5, 11]` → `norm:ebu:-16:-1.5:11`.
- A deliberate number formatter matching the proxy grammar: floats capped at 3 decimals, minimal rendering (`30` not `30.0`, `12.5` never `12.50`), integers rendered as integers. Tested hard.
- Option segments are rendered in the order given by the caller (the proxy normalizes server-side; the client stays predictable and simple). Values are rendered, not validated — the proxy remains the validator of value domains and cross-key rules.
- `raw:` passthrough continues to work and composes: when both `raw:` and typed keys are given, that is an error (ambiguous intent).
- Friendly-name aliases (`bitrate:` → `br:`) explicitly deferred — additive, post-MVP.

## Capabilities

### New Capabilities

- `options-rendering`: typed short-key option rendering, array handling for multi-part options, and canonical number formatting.

### Modified Capabilities

- `url-building`: the options segment can now come from typed keys, not only `raw:`/defaults; mixing `raw:` with typed keys is rejected.

## Impact

- New code: `lib/audioproxy/options.rb` (or equivalent module) with the key table and number formatter; wiring in `UrlBuilder`/`url_for`.
- Tests: number-formatting suite (the cache-key-stability trap), per-key rendering, array options, raw/typed mixing error.
- Depends on: `add-gem-core-signing`.
- Downstream: `add-rails-integration` helpers and `add-activestorage-resolution` pass typed options through unchanged.
