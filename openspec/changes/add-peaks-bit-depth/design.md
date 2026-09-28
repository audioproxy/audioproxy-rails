## Context

The gem renders option keys and does not interpret them. `KEYS` is a flat list, `ALIASES` maps spelled-out names onto it, and `CANONICAL` is derived by inverting that map. Adding an option is therefore two entries and the tests that enumerate them, which is why this change is small enough that the design is mostly a record of one naming decision.

## Goals / Non-Goals

**Goals:**

- A Rails caller can reach `pk_bits` with either spelling.
- The alias does not collide with the one that already exists for `bd`.

**Non-Goals:**

- Validating the value. The proxy is the validator, per the existing requirement.
- Expressing a minimum proxy version in code. The gem has never modelled one.

## Decisions

**`peak_bits`, not `bit_depth`.** `bit_depth` is already the alias for `bd`, which names the sample format of encoded output. `pk_bits` names the width of values in a serialization that is never encoded. Reusing the spelling would make one word mean two things depending on the format beside it, and the gem's alias table is a flat map with no format context to disambiguate with.

The `peak_` prefix already carries this distinction for `peak_count`→`pts` and `peak_format`→`pk_fmt`, so the pattern is established rather than invented here.

*Alternative considered:* `peaks_bit_depth`, closer to the proxy's own wording. Rejected as longer than its two siblings without being clearer.

## Risks / Trade-offs

**A caller on an older proxy gets a 422 rather than a clear message.** → Accepted, and unchanged from every other option the gem has shipped ahead of a proxy release. The README's "Minimum proxy version" section is the place that records it.

**Ordering.** This must not be released before the proxy change. → The gem raising on an unknown key is not the risk; the risk is a released gem that renders a segment no deployed proxy accepts. Release after, not alongside.

## Review

Reviewed by `kimi-k2.7-code` via opencode, read-only, against a committed tree, with the proxy's
source and tags available so the implementation's four claims (the proxy's field is `peak_bits`,
`pk_bits` shipped in `v0.8.0`, older proxies 422 it as an unknown key, and the tasks closed by note
rather than code) could be checked from primary sources. A self-review was written first and kept
sealed until the reviewer returned.

Both came back clean, and every claim was confirmed on both sides. The one gap was the author's: no
test set `peak_bits` through `default_options`, which is how an app standardising on peaks.js would
actually use it. It worked when run in a process, and is now pinned.

The brief did not name the view helpers, so they were checked afterwards: they pass options through
to `url_for` untouched and keep no key list of their own that could drift. The `bit_depth` confusion
the alias decision guards against also fails loudly at the proxy, which answers `bd` under `f:peaks`
with a 422 (`@peaks_unsupported`), so the likeliest peaks.js mistake cannot quietly yield 16-bit data.
