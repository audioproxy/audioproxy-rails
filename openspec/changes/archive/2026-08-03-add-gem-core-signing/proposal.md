## Why

Rails applications need to generate signed variant URLs for the audioproxy server, and today there is no Ruby client: every app would have to hand-roll HMAC signing, source encoding, and the proxy's URL grammar — and get every byte identical to the reference implementation or produce URLs that 403. This change creates the gem's Rails-free core: configuration, URL assembly, and signing that is proven byte-compatible against the proxy's published known-answer test (KAT) vectors.

## What Changes

- Builds on the skeleton from `add-plugin-scaffold`: all code in this slice lives in the Rails-free `Audioproxy` namespace (so a pure-Ruby extraction stays a later `git mv`, not a rewrite) and touches nothing under `Audioproxy::Rails`.
- New `Audioproxy::Config`: endpoint (full base URL: scheme + host + optional path prefix), hex `key`/`salt` (decoded to binary), `unsigned` flag for dev, default options.
- New `Audioproxy::UrlBuilder`: assembles `{endpoint}/{signature}/{options}/{source}` — `enc/` base64url source encoding by default, HMAC-SHA256 signature (`base64url(HMAC-SHA256(key, salt ‖ rest-of-path))`, unpadded) matching the proxy's `AudioProxy.Signature` byte-for-byte.
- New `Audioproxy.url_for(source, **opts)` module-level entry point, usable in jobs/mailers/serializers without Rails.
- Options in this slice are the `raw:` passthrough only (a pre-rendered options string); the typed short-key option rendering (`f:`, `br:`, `t:`, number formatting) lands in the follow-up change `add-options-rendering`.
- `unsigned: true` emits the literal `insecure` signature segment (parity with the proxy's `AP_ALLOW_INSECURE` dev mode).
- Per-call `endpoint:` override on `url_for` for multi-region / second proxy instances / cross-env URL generation.
- Endpoint path prefixes (`https://cdn.example.com/audio`) work by construction — the HMAC covers everything after the signature segment, so a CDN routing a prefix to the proxy does not disturb signing. Stated and tested, not assumed.
- The proxy's KAT vectors vendored as Minitest fixtures — cross-implementation compatibility by test, not by convention.

## Capabilities

### New Capabilities

- `configuration`: how the gem is configured — endpoint, hex key/salt decoding, unsigned flag, default options, validation of incomplete config.
- `url-signing`: signature computation and the signed/insecure URL path shape, byte-compatible with the proxy's reference signer.
- `url-building`: URL assembly — endpoint joining (including path prefix), `enc/` source encoding, `raw:` options passthrough, per-call endpoint override, `Audioproxy.url_for`.

### Modified Capabilities

_None — greenfield repository._

## Impact

- New code: `lib/audioproxy/config.rb`, `lib/audioproxy/url_builder.rb`, module-level API in `lib/audioproxy.rb`, Minitest suite with vendored KAT vectors.
- Dependencies: Ruby stdlib only (`openssl` for HMAC, base64url encoding). No Rails, no ActiveSupport in this slice.
- Depends on: `add-plugin-scaffold` (gem skeleton, namespace split, test harness).
- Downstream: `add-options-rendering`, `add-rails-integration`, and `add-activestorage-resolution` all build on this core.
- Upstream contract: the audioproxy server's `AudioProxy.Signature` and `AudioProxy.Source` modules define the bytes this gem must produce; the vendored KAT vectors pin that contract.
