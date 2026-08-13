# Tasks

## 1. Harness

- [ ] 1.1 Decide the source strategy (`local://` with a mounted fixture root vs an `https://` source) and record it in `design.md`
- [ ] 1.2 Boot `ghcr.io/audioproxy/audioproxy` at a pinned tag with the key, salt and source root the tests sign against
- [ ] 1.3 A `:server` test tag, excluded from `bin/test` by default and skipped (not failed) when no container is reachable
- [ ] 1.4 A failure message that names the pinned proxy tag, so a version mismatch is legible

## 2. Round-trips that have never been made

- [ ] 2.1 A signed URL from `url_for` renders: 200, not 403
- [ ] 2.2 A tampered path is refused with 403, so 2.1 proves something
- [ ] 2.3 An `unsigned: true` URL renders under `AP_ALLOW_INSECURE`
- [ ] 2.4 A typed-options URL (`f:opus/br:96`) renders the variant it names

## 3. Expiry (retires add-expiring-urls task 3.4)

- [ ] 3.1 Renders before `exp`
- [ ] 3.2 410 after `exp` — not 403, not 422
- [ ] 3.3 The boundary: a request in the second `exp` names is still served, confirming D5
- [ ] 3.4 Copy the proxy's `exp`-bearing known-answer vector into `test/fixtures/signature_vectors.rb` if one is published; never regenerate from this gem's own signer

## 4. CI and docs

- [ ] 4.1 A CI job running the `:server` group; decide gating vs advisory
- [ ] 4.2 README: how to run the round-trip tests locally, and what they need
- [ ] 4.3 Record who advances the pinned tag when the proxy releases
