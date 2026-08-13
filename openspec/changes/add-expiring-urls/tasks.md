# Tasks

## 1. Rendering and building

- [x] 1.1 `Audioproxy::Options`: `exp` renders as bare integer seconds
- [x] 1.2 `Audioproxy::UrlBuilder`: `expires_in:`/`expires_at:` handling; duration/Integer/Time-like coercion; mutual-exclusion, non-positive, past-timestamp, and bad-type raises
- [x] 1.3 `Audioproxy::Config`: optional `expires_in` default (nil = eternal); per-call nil opt-out

## 2. Helpers

- [x] 2.1 Forward both keywords through every URL-building helper

## 3. Tests

- [x] 3.1 Frozen-clock arithmetic for duration, Integer, Time-like, and TimeWithZone inputs; exact `exp:` segment assertion
- [x] 3.2 Every raise path (both keywords, zero/negative, past, wrong type)
- [x] 3.3 Global default + override + opt-out matrix
- [ ] 3.4 **Deferred** — `:server`-tagged round-trip against a proxy container with exp support: renders before expiry, 410 after; copy the server's exp-bearing signature vector into fixtures if one is published. Gated on the proxy tagging a release that carries `exp` (merged as `2398fd5`, unreleased as of `v0.5.0`), and on this gem gaining a container harness it does not have yet. See design.md Risks.
- [x] 3.5 Signer isolation test untouched and still green (exp is ordinary path bytes)

## 4. Docs

- [x] 4.1 README: keywords, global default, rotation-for-free note, minimum proxy version
- [x] 4.2 CHANGELOG entry
