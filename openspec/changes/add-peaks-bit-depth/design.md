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
