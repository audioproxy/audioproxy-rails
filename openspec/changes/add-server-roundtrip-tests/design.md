# Design

## Context

The gem's correctness has only ever been checked against bytes — the proxy's published known-answer
vectors, and readings of the proxy's source. This change adds the first assertion that a URL built
here is *accepted by a running proxy*, and with it the `:server` infrastructure the gem has never
had.

Everything below was verified against `ghcr.io/audioproxy/audioproxy:0.6.0` rather than reasoned
about, which is the entire point of the change. Where a decision records a status code or a
boundary, it was observed.

## Decisions

### D1. The source is `local://` over a bind-mounted fixture root the tests generate

*(Resolves the proposal's first open question, and task 1.1.)*

The proxy must resolve whatever source it is handed. The candidates were `local://` with
`AP_LOCAL_ROOT` bind-mounted, or an `https://` source served by something.

`local://` wins, and not narrowly. An `https://` source needs a second container or an in-process
server reachable *from inside the container* — which on Docker Desktop means
`host.docker.internal`, on Linux CI means something else, and in both cases adds a moving part whose
failures look exactly like the failures the suite exists to detect. `local://` needs a directory and
a `-v` flag. The proxy also treats the root as the allowlist for disk, so no `AP_SOURCE_ALLOWLIST`
is involved.

The fixture is a one-second 8 kHz mono PCM sine, **generated in Ruby at test time** into
`tmp/roundtrip-root/` rather than committed. It is sixteen kilobytes of `Array#pack`, it needs no
ffmpeg on the developer's machine to produce, and `tmp/` is already gitignored — so the repository
gains no binary and the gemspec (which globs `lib/` only) is untouched. ffmpeg lives in the
container, which is where the transcode happens.

The source string the tests sign is therefore `local://tone.wav`. The root does not appear in it:
the proxy deliberately keeps `AP_LOCAL_ROOT` out of a source's identity, so the same relative path
is the same variant wherever it is mounted.

### D2. The image is pinned to `0.6.0`, and pulled `--platform linux/amd64`

`ghcr.io/audioproxy/audioproxy:0.6.0` is the release that added `exp`. Pinned rather than `latest`
for the reason the proposal gives: a suite that follows upstream turns an upstream change into a
failure here with no commit here to blame.

**The published manifest is amd64-only** — a plain `docker pull` on Apple Silicon fails with `no
matching manifest for linux/arm64/v8`. The harness passes `--platform linux/amd64` unconditionally,
which is a no-op on amd64 hosts and selects emulation on arm64 ones. Emulated boot measured at
around three seconds to a 200 on `/health`; the readiness poll allows sixty.

This is a fact about the current publication rather than a permanent one. If the proxy ever
publishes arm64, the flag becomes redundant rather than wrong, so nothing here needs to change on
that day.

### D3. The `:server` tag is an opt-in environment variable, and it skips rather than fails

Minitest has no tag facility, so the tag is a module: `ServerRoundtrip`, included by the test case,
whose `setup` calls `skip` unless `AUDIOPROXY_SERVER_TESTS` is set. `bin/test` therefore stays a
fast, Docker-free unit run on a laptop with no network — the group reports as skipped, which is
visible without being a failure.

`bin/test-server` sets the variable and defaults to `test/server`. Opting in is not the same as
demanding a container: with the variable set and no reachable Docker, the group still skips, because
a contributor who opted in on a machine whose Docker daemon is stopped has a broken environment
rather than a broken gem.

CI closes the hole that opens, and closes it *outside* the suite: the round-trip job runs an
explicit `docker pull` step before `bin/test-server`. A ghcr outage fails that step, by name, rather
than laundering itself into a silent skip.

### D4. One container serves the whole group

The container runs with `AP_KEY`, `AP_SALT` *and* `AP_ALLOW_INSECURE=true` together. This is not a
compromise between the signed and unsigned cases: `AudioProxy.Signature.verify/2` special-cases only
the literal `insecure` segment, and every other signature still goes through the HMAC comparison.
So one container proves both that a signed URL verifies and that an `insecure` one is admitted,
without weakening the first.

It boots once for the group (`Minitest.after_run` stops it), because an emulated BEAM boot per test
would dominate the runtime.

The key and salt are `test/fixtures/signature_vectors.rb`'s, reused rather than reinvented so that
the bytes the round-trip exercises are the bytes the known-answer vectors pin.

### D5. **Amendment: a tampered URL is answered `401`, not `403`**

The proposal, the delta spec's *"The signature is load-bearing"* scenario, and task 2.2 all said
`403`. **Observed: `401`, with body `{"error":"invalid_signature","message":"Invalid or missing
signature"}`.**

This is not a near-miss worth glossing. `AudioProxy.ErrorJSON` maps `:invalid_signature` to the
`401` row, and `AudioProxy.Router`'s moduledoc says so outright ("an unsigned or badly-signed
request is a 401 from there"). §5 of the proxy's API doc has *no* `403` at all: source failures are
a blind `404` precisely so that a distinct status cannot become an existence oracle. The `403` in
this change's artifacts was an assumption that had never been checked, which is the exact species of
error the change exists to catch — it is mildly satisfying that the first thing the harness found
was in the brief that commissioned it.

The delta spec and `tasks.md` are amended in the same commit as the code, per the repo's rule that
artifacts and behaviour never disagree. The assertion is written as `assert_equal 401` rather than
`assert_not_equal 200`, so if the proxy ever moves it, this suite says which way.

### D6. The boundary test guards against the second rolling over

`add-expiring-urls` D5 claims the proxy's check is `now > exp`, so the second `exp` names is still
served. Verifying that needs a request that *lands inside that second*, which is a race against the
clock by construction.

The test builds `expires_at: now + 3`, spins until `Time.now.to_i == exp`, requests, and then
asserts the second had not rolled over before it evaluates the status. If it did roll over, the run
proves nothing and the test retries; after three attempts it skips rather than reporting a pass it
did not earn. Measured: three consecutive attempts landed in-second with the transcode included, so
the retry is a backstop rather than the normal path.

This assumes the container's clock and the host's agree, which holds for Docker Desktop and for
Linux CI, where the container shares the host kernel's clock. A skew large enough to break it would
break the `410` test too, and in a direction that is loud.

### D7. CI runs the group in its own job, visible but not required

*(Resolves the proposal's second open question.)*

A separate `roundtrip` job, on the same triggers as the rest of CI. It goes red on failure — there
is no `continue-on-error` laundering the result — but it is deliberately **not** added to branch
protection's required checks. The reason is the one the proposal names: a required job that pulls a
third-party image makes every merge depend on ghcr being reachable, and this gem's unit suite is
already the real safety net. Red-and-visible buys the signal; required would buy an outage.

That "not required" is a repository *setting* and cannot be asserted from a workflow file, so it is
written down here and in the README rather than encoded.

### D8. The pin advances as part of the proxy's release checklist

*(Resolves the proposal's third open question, and task 4.3.)*

The maintainer of this gem advances `PROXY_IMAGE_TAG` when the proxy releases. It is recorded in the
README next to the harness, so the person running the round-trip tests reads it, and in the
container constant, so the person editing the harness does. A pinned tag nobody advances stops
testing anything interesting; the failure mode of a stale pin is silence, so the reminder belongs
where it is seen rather than in a process document.

## Out of scope

- `/info` and peaks round-trips (`add-info-and-peaks-urls` owns those).
- The representation hook (`add-representation-hook`).
- Variant-store, S3 and redirect-mode behaviour: the container runs with no `AP_VARIANT_STORE`, so
  every response here is a live render. Cache-HIT paths and the presigned-TTL clamp are the proxy's
  own tests to run.
- An `exp`-bearing known-answer vector, which `v0.6.0` does not publish (task 3.4, settled in the
  proposal).
