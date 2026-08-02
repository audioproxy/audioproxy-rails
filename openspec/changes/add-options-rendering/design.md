## Context

The proxy's options grammar (its `AudioProxy.Options` module) is `/`-separated `key:value` segments with fourteen keys (`bd br cb ch dl f fade gain norm pk_fmt pts q sr t`). Two properties of that grammar matter to a client:

- **Numbers have one canonical spelling.** The proxy caps decimals at 3 places at parse time and renders minimally (`30`, not `30.0`; `12.5`, never `12.50`). Its cache key hashes the normalized options string. A client that renders `12.50` produces a URL that still *works* (the proxy re-normalizes) but is a distinct URL — distinct CDN cache entry, distinct browser cache entry — for the identical variant. Worse, values with more than 3 decimals are rejected server-side with a 422 (`:excessive_precision`), not rounded.
- **Multi-part values are colon-joined**: `t:START[:DURATION]`, `fade:IN[:OUT]`, `norm:ebu[:I[:TP[:LRA]]]`.

The core slice (`add-gem-core-signing`) ships `raw:` passthrough only; this slice adds the typed layer.

## Goals / Non-Goals

**Goals:**

- Typed keyword arguments for all fourteen proxy option keys, canonical short names.
- Array values for multi-part options, colon-joined.
- A number formatter that provably matches the proxy's rendering for every value a client can legally send.
- Clear failure for ambiguous input (`raw:` + typed keys together).

**Non-Goals:**

- Client-side validation of value domains or cross-key rules (bitrate ranges, `br`-excludes-`q`, fade-fits-trim…). The proxy owns validation; duplicating it here means two drifting rule sets.
- Friendly-name aliases (`bitrate:` → `br:`) — additive sugar, deferred.
- Client-side normalization (sorting keys, materializing defaults). The client renders what it was given, in the order given; the proxy normalizes for cache identity.

## Decisions

### D1: Render, don't validate

Each typed key renders its value into a segment; no domain checks beyond what rendering itself requires (see D2). Rationale: the proxy returns structured 422s naming the offending segment, its rules are versioned with the server, and a stale client-side copy of those rules would reject URLs a newer proxy accepts. One exception class: values the formatter *cannot* render faithfully are errors (D2), because silently mangling a number is worse than either accepting or rejecting it.

### D2: The number formatter is strict about precision

`format_number(value)`:
- Integers → `Integer#to_s`.
- Floats equal to their truncation → rendered as integers (`30.0` → `"30"`).
- Other floats → rendered with at most 3 decimal places, trailing zeros trimmed (`12.5`, `0.125`).
- A float that does not survive the 3-decimal round-trip (`0.1234`) raises `ArgumentError` — mirroring the proxy's `:excessive_precision` rejection instead of rounding, so a client bug surfaces at URL-build time, not as a proxy 422 in production.
- Rationals/BigDecimals accepted and rendered through the same path; strings passed through verbatim (caller opted out of formatting).
- Negative zero collapses to `"0"` (the proxy does the same at its decimal funnel).

Implementation note: render via an explicit decimal path (e.g. `format("%.3f")` then trim), not `Float#to_s` — `Float#to_s` produces `1.0e-05`-style exponent forms the grammar rejects.

### D3: Multi-part options are arrays, scalars auto-wrap

`t: [12.5, 30]` → `t:12.5:30`; `t: 12.5` → `t:12.5` (single-element case is the scalar). `norm: :ebu` → `norm:ebu`; `norm: [:ebu, -16]` → `norm:ebu:-16`. Symbols render with `to_s` (`f: :opus` → `f:opus`). Each array element goes through the number formatter when numeric.

### D4: Caller order is preserved; `raw:` and typed keys are mutually exclusive

Segments render in the order the caller wrote the keywords (Ruby preserves keyword-argument order). No client-side sorting: sorting is the proxy's normalization concern, and a stable-but-different client order would just create a third spelling. `raw:` plus any typed key raises `ArgumentError` — two sources of truth for one segment string is ambiguity, not composition. `default_options` from config merge *under* per-call typed keys (per-call wins key-by-key); `raw:` in a call replaces defaults entirely.

### D5: Unknown keys raise

An unrecognized keyword (typo: `bt: 96`) raises `ArgumentError` listing the known keys, rather than rendering a segment the proxy will 422. This is grammar-shape knowledge (which keys exist), not value-domain knowledge, and the key list is small and stable.

## Risks / Trade-offs

- [Key list drifts as the proxy adds options] → The list is additive and small; a new proxy key needs one line here plus `raw:` always works as the escape hatch in the meantime.
- [No client-side sorting means visually different URLs for the same variant when callers reorder keywords] → Accepted: the alternative (client sorts) still can't match proxy normalization (defaults materialization), so it would be a half-normalization. Documented: callers wanting URL stability should keep argument order stable.
- [Strict precision errors may surprise callers doing float math (`0.1 + 0.2`)] → The error message names the value and the 3-decimal cap; docs recommend rounding explicitly at the call site.
