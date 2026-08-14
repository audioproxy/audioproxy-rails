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
`/tmp/audioproxy-fixtures` (overridable with `AUDIOPROXY_FIXTURE_ROOT`) rather than committed. It is
sixteen kilobytes of `Array#pack`, it needs no ffmpeg on the developer's machine to produce, and it
lives outside the repository — so the repository gains no binary and the gemspec (which globs `lib/`
only) is untouched. ffmpeg lives in the container, which is where the transcode happens.

A path under `/tmp` rather than the working tree because of how the mount has to work under D2; the
directory is also the one place the README's `-v` and CI's `services.volumes` must agree, so it is a
constant rather than a derived path. It is rewritten on every run: the directory outlives the run,
so a file left truncated by an interrupted one would otherwise be reused forever, and the symptom is
an ffmpeg decode failure inside the container that points nowhere near the cause.

The source string the tests sign is therefore `local://tone.wav`. The root does not appear in it:
the proxy deliberately keeps `AP_LOCAL_ROOT` out of a source's identity, so the same relative path
is the same variant wherever it is mounted.

### D2. **The gem does not start the proxy.** CI runs a service container; the README has the command

This decision replaces an earlier one, and the replacement is the more important half of this
design.

The first implementation orchestrated the container from Ruby: `docker run` through `Open3`, port
allocation, `/health` polling, `at_exit` cleanup, per-process container naming, label-based sweeps
of what a crashed run left behind. It worked. It was also about a hundred and twenty lines of
process management, and **every defect the outside review found was in that machinery rather than in
anything being tested** — a container leaked when boot timed out, a fixed name let a second local
run evict the first's container, a `free_port` bind-then-release race, and two places where the code
had drifted from this document.

None of those problems are about whether this gem builds correct URLs. They are the cost of having
written a container supervisor inside a test suite, and the cost was larger than the thing it
supervised.

So: **CI declares the proxy as a `services:` sidecar**, which is what service containers are for —
Actions owns the lifecycle, the port mapping and the readiness gate, all of which it already does
better than the Ruby did. **Locally, the README gives the `docker run` line.** The suite's entire
contract with the proxy is one environment variable holding its address.

What this costs is one manual step before running the group on a laptop. What it buys is that four
of the six review findings cease to exist rather than being fixed, and the harness becomes something
a reader can hold in their head.

The image is still pinned rather than tracking `latest`, for the reason the proposal gives: a suite
that follows upstream turns an upstream change into a failure here with no commit here to blame. It
is now pinned in two places — `PROXY_VERSION` in the harness and the image in the workflow — which
D8 makes safe.

**The published manifest is amd64-only**: a plain `docker pull` on Apple Silicon fails with `no
matching manifest for linux/arm64/v8`, so the README's command carries `--platform linux/amd64`. CI
runs on amd64 and needs no flag. If the proxy ever publishes arm64 the flag becomes redundant rather
than wrong.

#### The fixture and the service container's start order

Service containers start **before** checkout, so the workspace does not exist when the proxy boots
and its `AP_LOCAL_ROOT` cannot be a path inside it.

A bind mount is a live view, though, not a snapshot: `/tmp/audioproxy-fixtures` is mounted empty at
boot, the suite writes the generated WAV into it during `setup`, and the file is visible inside the
container immediately. Verified against a running container rather than assumed. The same path
appears in the README's `-v`, so one directory is correct in both places.

Docker creates that directory as root when it starts the service, which is why CI has one
`sudo chmod` step before the tests: the runner otherwise cannot write the fixture it just mounted.

### D3. The `:server` tag is one environment variable, and it distinguishes "not asked" from "asked and broken"

Minitest has no tag facility, so the tag is a module: `ServerRoundtrip`, included by the test case,
whose `setup` reads `AUDIOPROXY_PROXY_URL`.

The variable is both the opt-in and the address, which collapses what used to be two gates into one
and closes a hole in the process:

- **Unset — skip.** `bin/test` stays a fast, Docker-free unit run on a laptop with no network. A
  contributor who cannot pull an image can still make the suite green.
- **Set, and nothing answers — fail.** Setting it is a claim that a proxy is at that address. A run
  that was asked to exercise a proxy and silently exercised nothing is the one outcome this group
  must never produce, and the previous design could produce it: it skipped on unreachable Docker,
  and leaned on a separate CI step to notice. Now the suite notices, in every environment, without
  CI having to be complicit.

The error names the address, the underlying exception, the image to start, and the variable to unset
— because the reader hitting it is the one who has not read the README.

`bin/test-server` is gone with the orchestration it wrapped. `bin/test test/server` runs the group;
`bin/test` runs everything the environment allows.

### D4. One container serves the whole group

The container runs with `AP_KEY`, `AP_SALT` *and* `AP_ALLOW_INSECURE=true` together. This is not a
compromise between the signed and unsigned cases: `AudioProxy.Signature.verify/2` special-cases only
the literal `insecure` segment, and every other signature still goes through the HMAC comparison.
So one container proves both that a signed URL verifies and that an `insecure` one is admitted,
without weakening the first.

One container serves the whole group because nothing here needs a fresh one, and under D2 its
lifetime is not this suite's business at all: CI's service container lives for the job, and a local
one lives until its owner removes it.

Everything this decision used to say about *how* that container is stopped — `at_exit` versus
`Minitest.after_run`, registration ordering around the health wait, per-process names, labels to
find the leftovers of a crashed run — went with the orchestration in D2. Those were answers to
problems the suite no longer has.

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

The maintainer of this gem advances the pin when the proxy releases: `PROXY_VERSION` in
`test/support/server_roundtrip.rb` and the image in `.github/workflows/ci.yml`.

Two places, which would normally be a drift hazard — and here is not one, because the suite does not
trust either of them. `setup` asks `/health` what version actually answered and refuses to run
against anything else, naming both versions when they disagree. Advancing one and forgetting the
other is a named failure on the next CI run rather than a suite quietly testing a proxy nobody
intended. That check is also strictly better than what it replaced: it reports what *answered*
rather than what a constant claims was started, which is the difference between a pin and a wish.

It is recorded in the
README next to the harness, so the person running the round-trip tests reads it, and in the
container constant, so the person editing the harness does. A pinned tag nobody advances stops
testing anything interesting; the failure mode of a stale pin is silence, so the reminder belongs
where it is seen rather than in a process document.

## Review

Reviewed by `kimi-k2.7-code` via opencode, read-only, against a committed tree, with the proxy's
`v0.6.0` source available so the amendment in D5 could be checked from primary sources rather than
taken on trust. A self-review was written first and kept sealed until the reviewer returned.

Eight distinct issues between the two, **two of them found twice** — the usual near-zero overlap.

**The `exp` window was widened from one second to five**, and the wait is now derived from the `exp`
the gem emitted rather than a fixed `sleep 2.5`. `expires_in: 1` gave the first request a budget of
`2.0 - f` seconds — between one and two — to complete a cold ffmpeg render, measured at ~0.5s
locally. Under 2× margin on an emulated, loaded runner, and blowing it fails the *liveness*
assertion, reporting a gem defect where the only fact is a slow runner. Also applied: an assertion
that the signed round-trip actually signed, and unconditional fixture rewriting.

### Then the review's real lesson was applied, which was not any single finding

Four of the six findings — the leaked container, the fixed container name, the `free_port` race, and
both places where this document had drifted from the code — were defects *in the container
orchestration*, not in anything under test. Fixing them individually, which is what the first pass
did, left the orchestration in place and with it the capacity to grow more of the same.

D2 now deletes it: CI runs a service container and the README documents the local command. That is
the change this section would most want a reader to notice. The findings it retires were all real;
they simply stopped existing rather than being repaired.

### Rejected, with reasons

- **The reviewer's failure case for the expiry window is arithmetically wrong, and it carried its
  DO-NOT-SHIP verdict.** It had a URL built at `S+0.99` expiring when the proxy evaluates it at
  `S+1.01`. It does not: `v0.6.0:lib/audio_proxy/expiry.ex:125` is
  `defp now, do: System.system_time(:second)` — *integer* seconds — so the comparison there is
  `S+1 > S+1`, which is false. The concern is real and was fixed; the mechanism was not, and the
  finding was re-graded from HIGH to MEDIUM and from blocking to not.
- **CI going green on a group that skipped entirely** (self-review, LOW) was rejected as already
  covered by a `docker pull` step, and that reasoning is now obsolete along with the step. The
  concern is *better* answered under D3: a set `AUDIOPROXY_PROXY_URL` with nothing answering is a
  failure in every environment, so the suite no longer depends on CI noticing on its behalf.

## Out of scope

- `/info` and peaks round-trips (`add-info-and-peaks-urls` owns those).
- The representation hook (`add-representation-hook`).
- Variant-store, S3 and redirect-mode behaviour: the container runs with no `AP_VARIANT_STORE`, so
  every response here is a live render. Cache-HIT paths and the presigned-TTL clamp are the proxy's
  own tests to run.
- An `exp`-bearing known-answer vector, which `v0.6.0` does not publish (task 3.4, settled in the
  proposal).
