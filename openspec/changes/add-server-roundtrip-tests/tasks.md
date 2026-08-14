# Tasks

## 1. Harness

- [x] 1.1 Decide the source strategy (`local://` with a mounted fixture root vs an `https://` source) and record it in `design.md` — `local://` over a bind-mounted root the tests generate; see D1
- [x] 1.2 Run against `ghcr.io/audioproxy/audioproxy:0.6.0` (the release that added `exp`) with the key, salt and source root the tests sign against — as a CI service container and a documented `docker run` locally, rather than orchestrated from Ruby; see D2
- [x] 1.3 A `:server` test tag, excluded from `bin/test` by default — and, per D3, *failing* rather than skipping once a proxy address is supplied and nothing answers it
- [x] 1.4 A failure message that names the pinned proxy tag, so a version mismatch is legible — and a run-time `/health` check that names both versions and refuses to proceed

## 2. Round-trips that have never been made

- [x] 2.1 A signed URL from `url_for` renders: 200, not a refusal
- [x] 2.2 A tampered path is refused, so 2.1 proves something — **with 401, not the 403 this task assumed.** Observed on the harness's first run; the spec and `design.md` D5 are amended in the same commit
- [x] 2.3 An `unsigned: true` URL renders under `AP_ALLOW_INSECURE`
- [x] 2.4 A typed-options URL (`f:opus/br:96`) renders the variant it names

## 3. Expiry (retires add-expiring-urls task 3.4)

- [x] 3.1 Renders before `exp`
- [x] 3.2 410 after `exp` — not 401, not 422
- [x] 3.3 The boundary: a request in the second `exp` names is still served, confirming D5
- [x] 3.4 Copy the proxy's `exp`-bearing known-answer vector into `test/fixtures/signature_vectors.rb` if one is published — **checked at `v0.6.0`: none is.** The proxy still publishes the same two vectors this gem carries, neither with an `exp`. Nothing to copy, and nothing to synthesize; see proposal.md

## 4. CI and docs

- [x] 4.1 A CI job running the `:server` group; decide gating vs advisory — its own job, red on failure but not a required check; see D7
- [x] 4.2 README: how to run the round-trip tests locally, and what they need
- [x] 4.3 Record who advances the pinned tag when the proxy releases — the gem's maintainer, on the proxy's release; see D8, the README, and the `TAG` constant CI reads
