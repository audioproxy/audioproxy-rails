## 1. Vocabulary

- [x] 1.1 Check the alias table in D2 against the proxy's own option documentation; where the server
  already has a long name for an option, adopt it and amend D2 rather than shipping a second name

## 2. Resolution

- [x] 2.1 Add `Audioproxy::Options::ALIASES` (total over the fourteen canonical keys) and a
  resolution step that runs before the key-table lookup
- [x] 2.2 Raise `ArgumentError` naming both spellings when a call carries a canonical key and its
  alias for the same option
- [x] 2.3 Widen the unknown-key error to note that spelled-out aliases are accepted
- [x] 2.4 Tests: every alias renders as its canonical key, mixed vocabularies in one call, array
  forms under an alias, both-spellings conflict, near-miss alias still raising

## 3. Configuration and merge

- [x] 3.1 Widen `Config::OPTION_KEYS` to accept aliases in `default_options`, and reject both
  spellings of one option at assignment time
- [x] 3.2 Resolve aliases on both sides before the `default_options` merge, so an aliased default and
  a canonical per-call key are one key that overrides, in the default's position
- [x] 3.3 Tests: aliased default overridden by a canonical per-call key and the reverse, ordering
  preserved, conflicting defaults rejected at assignment

## 4. Durations

- [x] 4.1 Accept `ActiveSupport::Duration` for `t` and `fade` via an explicit `when` clause —
  `case … when Numeric` does not match it, since `Module#===` ignores `Duration`'s overridden
  `is_a?` — and feed it to the existing decimal path through `Duration#value`, the number the
  caller wrote (D6 amended: `to_r` renders the double's true value for `0.3.seconds` and is then
  rejected as excessive precision, while a plain `t: 0.3` renders)
- [x] 4.2 Raise `ArgumentError` for a `Duration` on any other key, so `br: 3.seconds` cannot render
  `br:3`
- [x] 4.3 Tests: `t: 30.seconds` → `t:30`, `fade: [1.5.seconds, 2.seconds]` → `fade:1.5:2`, durations
  mixed with numbers in one array, sub-second durations, `br: 3.seconds` raising

## 5. Byte-stability guard

- [x] 5.1 Test that an aliased call and its canonical equivalent produce identical URLs, signature
  included, across the multi-part and number-formatting cases, and that a `Duration` renders the
  same URL as the number of seconds it stands for. If this slice changes any rendered byte, it is
  wrong

## 6. Documentation

- [x] 6.1 README: add the alias column to the key table, state that both spellings are accepted and
  that the canonical short keys remain first-class (they are what `raw:` strings and the proxy's own
  error messages use), document the both-spellings error, and show `t: 30.seconds` for the
  time-valued keys
