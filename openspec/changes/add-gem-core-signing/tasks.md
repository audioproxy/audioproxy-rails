## 1. Module API

- [ ] 1.1 Add module-level `Audioproxy.configure`, `Audioproxy.config`, and `Audioproxy.url_for` to `lib/audioproxy.rb`, requiring the new core files; confirm the scaffold's Rails-free load test still passes

## 2. Configuration

- [ ] 2.1 Implement `Audioproxy::Config` with `endpoint`, `key`, `salt`, `unsigned`, `default_options` accessors
- [ ] 2.2 Implement eager hex→binary decoding for `key`/`salt` with `ArgumentError` on non-hex or odd-length input, naming the attribute
- [ ] 2.3 Implement endpoint validation: absolute http/https URL, optional path prefix, `ArgumentError` otherwise
- [ ] 2.4 Tests: valid/invalid hex, endpoint validation, default_options storage, `Audioproxy.configure` block wiring

## 3. Signer

- [ ] 3.1 Vendor the proxy KAT vectors into `test/fixtures/signature_vectors.rb` (hex key, hex salt, both path→signature pairs) with an origin comment and the Python generator snippet
- [ ] 3.2 Implement `Audioproxy::UrlBuilder` signing: HMAC-SHA256 over `salt + rest_of_path`, unpadded base64url output, raise on `rest_of_path` not starting with `/`
- [ ] 3.3 Tests: both KAT vectors match exactly; output is 43 chars of `[A-Za-z0-9_-]`, never padded; missing leading slash raises

## 4. URL builder

- [ ] 4.1 Implement `enc/` source encoding (unpadded base64url of the source string)
- [ ] 4.2 Implement options segment selection: `raw:` verbatim → configured `default_options` → literal `f:mp3` fallback
- [ ] 4.3 Implement URL assembly: endpoint (trailing-slash normalized) + `/{signature}/{options}/{source}`; wire `unsigned` (config and per-call) to the literal `insecure` segment; raise a named configuration error when signing without key/salt
- [ ] 4.4 Implement per-call `endpoint:` override without mutating global config
- [ ] 4.5 Tests: full URL shape, enc encoding of awkward sources (spaces, nested URLs, `%` bytes), raw passthrough, `f:mp3` fallback, unsigned shape, missing-key error, per-call endpoint override
- [ ] 4.6 Test: path-prefix endpoint (`https://cdn.example.com/audio`) yields byte-identical signature/options/source segments as a bare endpoint; trailing-slash endpoint yields no double slash

## 5. Wrap-up

- [ ] 5.1 README: configure (endpoint/key/salt/unsigned), `url_for` with `raw:` options, per-call endpoint override, note that typed options and Rails helpers are follow-up slices
- [ ] 5.2 Run full suite; verify a standalone `ruby -Ilib -r audioproxy` smoke script produces a URL the proxy's reference signer would verify (recompute expected signature in the test)
