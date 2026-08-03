## Context

The proxy's option keys are two-letter-ish abbreviations (`f`, `br`, `sr`, `bd`, `pk_fmt`) because
they are URL path segments and every byte is in the cache key. Ruby callers have no such constraint,
and `url_for(blob, f: :opus, br: 96, sr: 44100, ch: 1, bd: 24)` is a line you have to decode rather
than read.

`add-options-rendering` deliberately shipped only the canonical keys, and deferred aliases as
additive sugar. That deferral was safe: an unrecognized key raises today (D5 of that slice), so no
caller can depend on `bitrate:` doing anything, and adding it later cannot break a working call
site.

## Goals / Non-Goals

**Goals:**

- A spelled-out alias for every canonical key, usable per call and in `default_options`.
- Aliases resolve before rendering and before the defaults merge, so they are invisible to
  everything downstream.
- Ambiguity (both spellings of one key in one call) is an error.

**Non-Goals:**

- Replacing or deprecating the canonical short keys. They are the proxy's own vocabulary, they are
  what `raw:` strings and proxy error messages contain, and they stay first-class in the docs.
- Aliases for *values* (`format: :opus_audio`). Values are the proxy's domain (D1 of the previous
  slice); an alias vocabulary for them would be the client-side rule set that slice exists to avoid.
  D6 accepts an `ActiveSupport::Duration` where a number of seconds is already accepted, which is a
  Ruby *type* the caller may write the value in, not a second vocabulary of values.
- Multiple aliases per key. One alternative spelling, not a thesaurus.
- Anything that changes rendered bytes. If this slice changes a single URL, it is wrong.

## Decisions

### D1: Resolution is a pre-pass, not a second rendering path

`Options` gains an `ALIASES` hash and resolves keyword keys through it before the existing key-table
lookup. Everything after that point (rendering, array handling, number formatting, ordering,
validation) is untouched and unaware. Rationale: the previous slice's byte-correctness is pinned by
tests and known-answer vectors; a parallel path for aliased keys would be a second place for those
bytes to drift. One vocabulary reaches the renderer.

### D2: The alias vocabulary

| Canonical | Alias |
| --- | --- |
| `f` | `format` |
| `br` | `bitrate` |
| `q` | `quality` |
| `sr` | `sample_rate` |
| `ch` | `channels` |
| `bd` | `bit_depth` |
| `t` | `trim` |
| `fade` | `fade` |
| `gain` | `gain` |
| `norm` | `normalize` |
| `pts` | `points` |
| `pk_fmt` | `peaks_format` |
| `dl` | `download` |
| `cb` | `cache_buster` |

`fade` and `gain` are already words and alias to themselves, so the table stays total: every
canonical key has an entry, and "does this key have an alias" is never a question with two answers.

**This table must be checked against the proxy's own documentation before implementation.** The
names above are the obvious Ruby spellings, but if the proxy's docs already call `pts` something
other than "points" or `norm` something other than "normalize", its name wins. Inventing a second
vocabulary for the same concepts is the one way this slice can do lasting damage, and it is cheap to
avoid by reading the server's option docs first.

### D3: Resolve before merging defaults

`config.default_options = { bitrate: 96 }` followed by `url_for(source, br: 128)` renders `br:128`,
once. Resolution therefore happens on both sides before the merge, not on the merged hash and not
per call site. Rationale: the merge is key-by-key (D4 of the previous slice), and a merge over
unresolved keys would treat two spellings of one option as two options, emitting `br:96/br:128` for
what the caller plainly meant as an override. That is a plausible-but-wrong URL, which is the
failure class this gem exists to prevent.

Ordering follows the canonical key's position, so a default written as `bitrate:` and overridden by
`br:` keeps the default's slot, exactly as two canonical keys would.

### D4: Both spellings in one call raise

`url_for(source, bitrate: 96, br: 128)` raises `ArgumentError` naming both spellings. Rationale: the
same rule as `raw:` plus typed keys (D4 of the previous slice). Ruby's keyword collection would
silently keep both, and picking a winner by position would make the URL depend on argument order in
a way nothing else here does.

The same applies within `default_options`, checked at assignment time so it fails at boot.

### D5: Unknown keys keep raising, with a wider message

The unknown-key error already lists the canonical keys (D5 of the previous slice). It grows to note
that spelled-out aliases are accepted too, because the most likely near-miss after this slice is a
caller guessing an alias that is not in the table (`bit_rate:`, `samplerate:`). Listing all
twenty-eight accepted spellings in one error is noise; naming both vocabularies and listing the
canonical fourteen is the balance.

### D6: `ActiveSupport::Duration` is accepted for the time-valued keys

`t: 30.seconds`, `t: [12.5, 1.minute]`, `fade: [1.5.seconds, 2.seconds]` render exactly as the
equivalent numbers do. Accepted for `t` and `fade` only, which are the keys whose values *are*
seconds; a `Duration` anywhere else (`br: 3.seconds`) raises, because a bitrate expressed as a
duration is a bug, and rendering `br:3` from it would be a plausible-but-wrong URL of exactly the
kind this gem exists to catch. That is a judgement about which Ruby type carries meaning for a key,
not about the value's domain, so it does not reopen D1 of the previous slice.

Two things make this worth writing down rather than leaving to the implementer:

- **`Duration` is not caught by `case value when Numeric`.** It overrides `is_a?` to answer `true`
  for `Numeric`, but `Module#===` performs the real type check and ignores that override, so
  `Numeric === 30.seconds` is `false` and the `case` falls through to the `else` branch. Today that
  means `t: 30.seconds` raises `"must be numbers, strings or symbols, got ActiveSupport::Duration"`
  while `30.seconds.is_a?(Numeric)` is `true` — an error message the caller cannot act on. The
  implementation needs an explicit `when ActiveSupport::Duration`, and the misleading rejection is
  reason enough to do this here rather than defer it again.
- **Conversion is exact and already correct.** `Duration#to_r` gives `30/1` for `30.seconds` and
  `90/1` for `1.5.minutes`, so it feeds the existing `exact_decimal` path with no new number
  handling and no new rounding rules. Sub-second durations (`0.5.seconds`) work for the same reason.

Calendar-variable units (`1.month`, `1.year`) resolve through `Duration`'s own average-seconds
definition rather than a rule invented here. They are absurd as a trim and nothing stops them, which
is the same stance the gem takes on `br: 999999`.

This is the one place ActiveSupport buys something real in `Options`. The rest of the module stays
stdlib by preference rather than by rule (only `Signer` is bound by the extraction seam), and in
particular `ActiveSupport::NumberHelper.number_to_rounded` must **not** be used for rendering: it
rounds `0.1234` to `"0.123"` instead of raising, which is the failure D2 of the previous slice
exists to prevent, and its decimal separator comes from I18n, so under a `:de` locale it renders
`12.5` as `"12,5"` and the signed bytes of a URL would depend on the app's current locale.

## Risks / Trade-offs

- [Two vocabularies to keep in sync as the proxy adds keys] → A new proxy key needs two lines rather
  than one, and the table being total (D2) makes a missing alias visible rather than silent. Accepted.
- [The alias names could diverge from names the proxy later publishes for the same options] → The
  mitigation is checking the server's docs before implementing (D2), not after. If a conflict shows
  up later, the proxy's name is added and ours becomes a second alias, which is a widening rather
  than a break.
- [Callers mixing vocabularies within one call (`format: :opus, br: 96`) produce readable-but-
  inconsistent code] → Not an error. It renders correctly and unambiguously, and a house style is a
  linting matter, not a URL builder's business.
- [Accepting `Duration` for `t` and `fade` but not elsewhere is a per-key value rule, and the gem has
  none of those] → It is a rule about types, not values, and it exists to keep `br: 3.seconds` from
  rendering. If a later proxy key takes seconds, it joins the list; the list living next to
  `MULTI_PART_KEYS`, which is already per-key knowledge, keeps that cheap.
