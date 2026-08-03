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
