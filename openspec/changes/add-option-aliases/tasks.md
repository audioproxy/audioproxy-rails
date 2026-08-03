## 1. Vocabulary

- [ ] 1.1 Check the alias table in D2 against the proxy's own option documentation; where the server
  already has a long name for an option, adopt it and amend D2 rather than shipping a second name

## 2. Resolution

- [ ] 2.1 Add `Audioproxy::Options::ALIASES` (total over the fourteen canonical keys) and a
  resolution step that runs before the key-table lookup
- [ ] 2.2 Raise `ArgumentError` naming both spellings when a call carries a canonical key and its
  alias for the same option
- [ ] 2.3 Widen the unknown-key error to note that spelled-out aliases are accepted
- [ ] 2.4 Tests: every alias renders as its canonical key, mixed vocabularies in one call, array
  forms under an alias, both-spellings conflict, near-miss alias still raising

## 3. Configuration and merge

- [ ] 3.1 Widen `Config::OPTION_KEYS` to accept aliases in `default_options`, and reject both
  spellings of one option at assignment time
- [ ] 3.2 Resolve aliases on both sides before the `default_options` merge, so an aliased default and
  a canonical per-call key are one key that overrides, in the default's position
- [ ] 3.3 Tests: aliased default overridden by a canonical per-call key and the reverse, ordering
  preserved, conflicting defaults rejected at assignment

## 4. Byte-stability guard

- [ ] 4.1 Test that an aliased call and its canonical equivalent produce identical URLs, signature
  included, across the multi-part and number-formatting cases. If this slice changes any rendered
  byte, it is wrong

## 5. Documentation

- [ ] 5.1 README: add the alias column to the key table, state that both spellings are accepted and
  that the canonical short keys remain first-class (they are what `raw:` strings and the proxy's own
  error messages use), and document the both-spellings error
