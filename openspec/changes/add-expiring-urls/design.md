## Context

The proxy has gained expiring URLs (`audioproxy` `2398fd5`, merged and **unreleased** — `v0.5.0`
predates it by 27 commits). Three properties of that implementation constrain everything below, and
all three come from the proxy's own source and `docs/audio-proxy-api-v1.md` §3.5:

- **`exp` is a *request* option** (`lib/audio_proxy/options.ex`): parsed and validated in the options
  segment, covered by the signature as path bytes, and excluded from the canonical options string,
  the cache key and the ffmpeg args. Two URLs differing only in `exp` are one variant and one render.
- **The check is `now() > expires_at`** (`lib/audio_proxy/expiry.ex:66`), so the boundary is
  *exclusive*: a request arriving in the second `exp` names is still served. There is no clock-skew
  leeway, deliberately — "a generator that wants a margin adds it to its own timestamps".
- **The value is a bounded positive integer**, capped at `@max_expires_at 253_402_300_799`
  (9999-12-31T23:59:59Z). Out of bounds is a `422` invalid-option; a value *in the past* is valid
  grammar whose answer is `410`.

The gem side is arithmetic and ergonomics: nobody computes unix timestamps in a view. The Rails
spelling is `expires_in: 1.hour`.

This gem's standing failure mode governs the shape of the validation. A wrong byte does not raise —
it 403s (now 410s or 422s) at the proxy, far from the call site. So every input that could produce a
valid-looking URL for the wrong verdict is checked at call time.

## Goals / Non-Goals

**Goals:**

- `expires_in:` / `expires_at:` on `url_for`, forwarded unchanged by every view helper.
- An optional process-global `config.expires_in`, with a per-call opt-out.
- Every emitted `exp:` segment is an integer the proxy will accept, or the call raised instead.
- The variant half of the options segment stays byte-identical to the same call without an expiry,
  so "one variant, rotating URLs" is visible in the URL itself.

**Non-Goals:**

- Version-sniffing the proxy. An older proxy answers `exp:` with a `422`, which is loud and
  server-side. The README names the minimum version; the gem does not negotiate.
- `/info` expiry. That endpoint has no options segment and cannot carry a request option at all
  (proxy API doc §3.5); it is a separate change on the proxy side if demand appears.
- A `config.expires_at`. An absolute timestamp applied process-globally expires every URL the app
  will ever mint at one instant, which is never what anyone means.
- The `:server`-tagged round-trip (task 3.4). Deferred — see Risks.

## Decisions

### D1 — `exp` joins the option grammar, but only the builder may emit it

`Options::KEYS` gains `exp`, and `Options::ALIASES` gains `exp: :expires_at` — the proxy's own struct
field name, per the existing options-rendering D2 ("one vocabulary spelled twice, not a second
vocabulary"). `ALIASES` is documented as total over `KEYS`, and that invariant is worth more than
saving a line.

But `exp:` and `expires_at:` are **refused as ordinary typed options** — in `url_for`'s keyword
collection and in `config.default_options` — each with a message naming `expires_in:`/`expires_at:`
and `config.expires_in` instead. The reason is the house rule, not tidiness: an `exp:` written as a
plain option skips every check in D5, and the two things a caller most plausibly gets wrong (a
timestamp already in the past, a millisecond timestamp) both produce a perfectly valid-looking URL
whose only symptom is a `410` or a `422` at request time. `default_options: { exp: … }` is worse
still — an absolute timestamp frozen at boot, so every URL the process mints dies at the same second.

*Alternative considered:* let `exp:` behave like any other key, uniform with the rest of the grammar.
Rejected on the above. Uniformity is not worth a silent already-dead URL, and the escape hatch for a
caller who genuinely wants to hand-write the segment already exists: `raw:`.

### D1b — `exp` renders integers only

`Options` renders and does not validate (options-rendering D1), with a carve-out for values it
"cannot render faithfully". `exp: 1.5` is exactly that: the proxy's grammar has no decimal here, so
`exp:1.5` is a `422`. A non-Integer `exp` raises at the render layer rather than emitting a decimal.

### D2 — Expiry is a builder keyword, and its segment is appended last

`expires_in:`/`expires_at:` sit beside `raw:`, `endpoint:` and `unsigned:` in `url_for`'s signature,
not in `**typed`. The rendered `exp:` segment is appended after the variant options.

Position is not load-bearing for the proxy — `exp` never reaches the canonical string — so the choice
is free, and appending buys one property: the variant prefix of the options segment is byte-identical
to what the same call without an expiry produces. `f:opus/br:96` and `f:opus/br:96/exp:1767225600`
differ by a suffix, which makes the "same variant, fresh URL every render" story legible in a log or
a diff rather than something you take on trust.

### D3 — `raw:` and expiry compose, and a `raw:` that already carries `exp:` raises

`raw:` is mutually exclusive with typed option keys because two sources of truth for **one variant**
is ambiguity (url-building D4). Expiry is not a variant option, so that argument does not reach it:
`url_for(src, raw: "f:opus/br:96", expires_in: 1.hour)` renders `f:opus/br:96/exp:N`. Dropping the
expiry because the caller happened to use `raw:` would silently mint the eternal URL they asked not
to have — the plausible-but-wrong URL this gem exists to prevent.

The one interaction that does need a guard: a `raw:` string that already contains an `exp:` segment,
combined with an expiry from a keyword *or from `config.expires_in`*, produces two `exp:` segments
and a duplicate-option `422`. With a global default set, that is a failure the caller did not write
and cannot see at the call site. So the raw segment is scanned for an `exp:` segment, and the
collision raises. A `raw:` carrying `exp:` with no expiry in force still passes through untouched —
that is the escape hatch working as documented, unvalidated and on the caller's head.

### D4 — The clock is `Time.now`, read once per URL

`exp` is absolute unix seconds, so `Time.now.to_i` and `Time.current.to_i` are the same integer, and
`Time.now` needs no `Time.zone` — which this layer cannot assume is set, because `Audioproxy.url_for`
is documented as usable from any Ruby program with no Rails loaded.

Read **once** per `url_for` call and threaded through both the `expires_in` arithmetic and the
`expires_at` past-check, so the two can never disagree across a second boundary.

### D5 — Coercion and the raise table

`expires_in:` — `ActiveSupport::Duration` or `Integer` seconds:

| Input | Result |
|---|---|
| `1.hour`, `30.minutes`, `90` | `now + n` |
| `0`, `-1`, `-1.hour` | raises — a non-positive window is an already-dead URL |
| `1.5.seconds`, `0.5` | raises — whole seconds only, "round explicitly at the call site if that is what you mean", matching the precedent `Options.format_decimal` already sets |
| `"1h"`, `Date`, anything else | raises — no coercion |

`expires_at:` — `Time`, `DateTime`, `ActiveSupport::TimeWithZone`, or `Integer` unix seconds:

| Input | Result |
|---|---|
| a future `Time`-like | `value.to_i` |
| a future `Integer` | used as-is |
| at or before now | raises |
| `> 253_402_300_799` | raises — the proxy's own bound. This is the millisecond-timestamp typo (`…to_i * 1000`), which is otherwise a clean-looking URL and a `422` |
| `Date`, `String`, anything else | raises — `Date#to_time` is local midnight, which is a different instant per machine |

Both keywords together raises, per the url-building spec.

Two notes on the edges. `Time#to_i` truncates sub-second, so an `expires_at` of `x.7s` renders `x` —
at most one second *early*, which is the fail-safe direction. And the proxy's boundary is exclusive
(`now() > exp`) while this gem refuses `expires_at == now`; the gem is one second stricter than it
strictly must be, which costs nothing and keeps the rule statable as "must be in the future".

### D6 — `config.expires_in` is a duration, and the opt-out needs a sentinel

`config.expires_in` (nil by default) takes the same shapes and the same validation as the keyword,
checked at assignment so a typo fails at boot rather than in a mailer. It is a duration rather than a
timestamp for the reason in Non-Goals.

Distinguishing "did not pass `expires_in:`" from "passed `expires_in: nil`" needs a sentinel default
on the keyword parameter, because `nil` is a meaningful value here — it is the documented opt-out.
`expires_at: nil` opts out identically; asymmetry between the two would be a rule to remember for no
gain.

Precedence, per call: an explicit `expires_in:` or `expires_at:` (including `nil`) wins over
`config.expires_in`. Only the *per-call* pair is mutually exclusive — a global default plus a per-call
`expires_at:` is an override, not a conflict.

### D7 — `Signer` is untouched

`exp` is ordinary path bytes to it. The extraction seam and `signer_isolation_test.rb` stand exactly
as they are; the isolation test is re-run unchanged as task 3.5 rather than modified.

## Risks / Trade-offs

- **The proxy feature is unreleased.** `exp` is on the proxy's `main` (`2398fd5`) but no tag carries
  it. → The README names the minimum version as the first release containing `exp` and says so
  explicitly rather than inventing a number. Against any older proxy this feature fails loudly
  server-side with a `422`, so shipping early is harmless, not silently broken.
- **Task 3.4, the `:server` round-trip, is deferred.** It needs both a tagged proxy image and a
  container harness this gem does not have (no compose file, no `:server` tag, nothing in CI). The
  proxy also publishes no `exp`-bearing signature vector to copy into
  `test/fixtures/signature_vectors.rb`. → The task is rewritten as deferred and gated on the proxy
  release. Every other test in §3 runs against a frozen clock and asserts exact bytes, so the
  arithmetic is covered; what stays unproven until 3.4 lands is that the proxy agrees with our
  reading of its boundary semantics.
- **Whole-seconds-only rejects a spelling someone will try.** `expires_in: 1.5.seconds` raises. → The
  message says to round explicitly. The alternative — truncating silently — is the class of thing
  this gem raises about everywhere else.
- **`config.expires_in` makes every URL in the app rotate.** Combined with a CDN, that means every
  render is a fresh edge-cache entry even though it is one origin variant. → The README states it:
  the origin-side single-variant guarantee is real, the edge-side one is not, and `exp` costs edge
  cache entries whichever syntax carries it (proxy API doc §3.5).

## Open Questions

- Whether `expires_in:` should also accept a `Float` of whole value (`3600.0`). Currently it does not
  — `Integer` and `Duration` only. Easy to add later; adding it now would be guessing at a call site
  nobody has written.
