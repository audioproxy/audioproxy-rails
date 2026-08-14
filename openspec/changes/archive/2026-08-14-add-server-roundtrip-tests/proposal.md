# Verify Generated URLs Against a Real Proxy

## Why

Every claim this gem makes about correctness is currently a claim about *bytes*, checked against
either the proxy's published known-answer vectors or a reading of the proxy's source. Nothing in the
suite has ever asked a running proxy whether a URL this gem built actually works.

That gap has been visible for a while and was named explicitly by `add-expiring-urls`, whose task
3.4 was deferred for exactly this reason and is the immediate motivation here. Expiring URLs are the
first feature whose behaviour is *not* fully expressible as a byte comparison: `exp:1767229200` is a
correct-looking segment whether or not the proxy agrees about when it expires, whether the boundary
is inclusive or exclusive, and whether the refusal is a `410` or a `422`. The gem currently asserts
the exclusive boundary on the strength of reading `expiry.ex:66`. Two independent readings agreed
(the implementer's and an outside reviewer's), which is worth something and is not the same as
having asked.

The gem also has **no `:server` test infrastructure at all** — no compose file, no tagged-test
convention, nothing in CI. So this is not "add one test"; it is the harness plus its first use. That
is why it is its own change rather than a loose end appended to the last one.

The proxy publishes `ghcr.io/audioproxy/audioproxy` (tagged `{version}`, `{major.minor}` and
`latest`), so the container side needs building, not inventing. This gem's CI already carries a
commented-out `services:` block from the generator, which is roughly the shape the answer takes.

## What Changes

- A `:server`-tagged test group, **excluded from `bin/test` by default** and run explicitly. The
  default suite must stay a fast, dependency-free unit run that works on a laptop with no Docker; a
  contributor who cannot pull an image must still be able to make the suite green.
- A harness that boots `ghcr.io/audioproxy/audioproxy` at a pinned tag, configured with the same key
  and salt the tests sign with, over a source the container can actually resolve.
- The first round-trips, in rough order of what they prove:
  - **A plain signed URL renders.** This is the assertion that has never been made: that a URL from
    `url_for` is accepted by a real proxy at all. Everything else is a refinement of it.
  - **An unsigned URL renders** under `AP_ALLOW_INSECURE`, matching `config.unsigned = true`.
  - **A tampered URL is refused**, so the test proves the signature is load-bearing rather than that
    the proxy is permissive.
  - **Expiring URLs**, the deferred slice: renders before `exp`, `410` after, and the boundary
    behaves as `add-expiring-urls` D5 claims. This is the one that retires the outstanding task.
- If the proxy publishes an `exp`-bearing known-answer vector, copy it into
  `test/fixtures/signature_vectors.rb`. Never regenerate vectors from this gem's own signer.
- CI: a job that runs the tagged group. Whether it gates merges or is advisory is an open question
  below.

## Coupling and sequencing

**Ungated.** The proxy released `v0.6.0` on 2026-08-13 and it carries `exp` (the merge `2398fd5` is
an ancestor of the tag; `expiry.ex`'s `now() > expires_at` and `parse_value("exp", …)` are both
present in the tagged tree). Pin `ghcr.io/audioproxy/audioproxy:0.6.0`. Nothing blocks this change
now.

Pin an explicit tag rather than `latest`. A suite that silently follows the proxy's newest release
turns an upstream change into a failure in this repo with no commit here to blame, and the whole
point of this harness is to be the place where disagreement between the two is *legible*.

**No `exp`-bearing known-answer vector exists to copy, and this is settled rather than pending.**
`v0.6.0`'s `test/audio_proxy/signature_test.exs` still publishes the same two vectors this gem
already carries (`/f:opus/br:96/plain/…` and `/info/plain/…`), neither with an options segment
carrying `exp`. Signing is agnostic to what the path bytes mean, so an `exp`-bearing vector would
add nothing to the *signer* contract — which is exactly why the round-trip below, not a vector, is
what actually verifies expiry. If the proxy ever publishes one, copy it; do not synthesize one here,
and never regenerate any vector from this gem's own signer.

## Capabilities

### New Capabilities

- `server-roundtrip`: URLs this gem builds are verified against a running proxy, in a test group
  that is opt-in and pinned to an explicit proxy version.

### Modified Capabilities

<!-- none: this verifies existing behaviour rather than changing it -->

## Impact

- Added: a `:server` test group and its harness, a pinned proxy image tag, a CI job, and
  documentation of how to run it locally.
- Modified: `bin/test` (to exclude the tagged group by default), CI workflow, README (a short
  "running the round-trip tests" note), and `add-expiring-urls`' archived task 3.4 is retired here.
- No runtime code changes, and no new runtime dependencies. Whatever this needs is development-only.
- Estimated ~200 LOC, most of it harness rather than assertions.

## Open Questions

- **Source strategy.** The proxy must resolve the source it is handed. `local://` with a mounted
  fixture directory (`AP_LOCAL_ROOT`) is the fewest moving parts; an `https://` source needs
  something to serve it. This decides the harness's shape and belongs in `design.md`.
- **Does CI gate on it?** A required job that pulls an image makes every PR depend on ghcr being up
  and on the pinned tag still existing. Advisory-but-visible may be the better trade for a gem whose
  unit suite is already the real safety net.
- **Who bumps the pin?** A pinned tag that nobody advances stops testing anything interesting. This
  probably wants to be part of the checklist when the proxy releases, which is a process answer
  rather than a code one.
