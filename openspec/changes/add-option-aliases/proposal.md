## Why

`add-options-rendering` shipped the proxy's own short keys as keyword arguments:
`url_for(source, f: :opus, br: 96, sr: 44100, pk_fmt: :json)`. That is the grammar the proxy speaks,
and it stays first-class. It is also unreadable at a glance in an app that touches audio options
twice a year, and it reads nothing like the Rails code around it.

This slice adds spelled-out aliases (`format:`, `bitrate:`, `sample_rate:`, `peak_format:`) that
resolve to the canonical short keys before anything is rendered. It was deferred out of
`add-options-rendering` as additive sugar; this is the slice that adds it.

Nothing about the URLs changes. An alias resolves to its canonical key and then goes through exactly
the rendering that already exists, so the bytes, the ordering rules and the cache keys are the ones
the previous slice pinned.

## What Changes

- An alias table mapping spelled-out names to the fourteen canonical keys. `bitrate:` → `br:`,
  `sample_rate:` → `sr:`, `peak_format:` → `pk_fmt:`, and so on. Keys whose short name is already a
  word (`fade:`, `gain:`, `norm:` as `normalize:`) are covered by the same table rather than special
  cased.
- Aliases are accepted anywhere typed keys are: per-call keyword arguments and
  `config.default_options`.
- Resolution happens before the `default_options` merge, so a default written as `bitrate: 96` and a
  per-call `br: 128` are one key that overrides, not two segments that both render.
- Giving both spellings of the same key in one call raises `ArgumentError`, on the same reasoning
  that rejects `raw:` alongside typed keys: two sources of truth for one segment is ambiguity.
- The unknown-key error grows to mention that aliases exist, so a caller who guessed
  `bit_rate:` is pointed at both spellings.
- `ActiveSupport::Duration` is accepted for the two keys whose values are seconds: `t: 30.seconds`,
  `fade: [1.5.seconds, 2.seconds]`. Today those raise, and misleadingly — `Duration` answers `true`
  to `is_a?(Numeric)` but is not matched by `case … when Numeric`, so the caller gets "must be
  numbers" for something that says it is one. Same slice, same shape: a Rails-idiomatic spelling
  resolving to bytes that do not change.

## Capabilities

### Modified Capabilities

- `options-rendering`: option keys may be written as spelled-out aliases as well as the proxy's
  canonical short keys, and the time-valued keys accept an `ActiveSupport::Duration`.

## Impact

- New code: an alias table and a resolution step in `Audioproxy::Options`; `Config::OPTION_KEYS`
  widens to accept aliases in `default_options`.
- No change to rendering, ordering, number formatting, or signing. The existing tests for those
  should pass untouched, which is the point.
- Tests: alias resolution per key, alias in `default_options` merging against a canonical per-call
  key, both-spellings conflict, unknown key still raising.
- Depends on: `add-options-rendering`.
- Downstream: none. `add-rails-integration` and `add-activestorage-resolution` pass options through
  and do not care which spelling arrived.
