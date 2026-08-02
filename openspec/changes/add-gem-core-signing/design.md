## Context

The audioproxy server serves audio variants at signed URLs of the shape:

```
{endpoint}/{signature}/{options}/{source}
```

- `signature` = `base64url(HMAC-SHA256(key, salt ‖ rest-of-path))`, **unpadded**, where `rest-of-path` is the exact byte sequence after the signature segment, **leading `/` included**. Key and salt are hex strings decoded to binary before use. The literal segment `insecure` is accepted by the proxy only when its `AP_ALLOW_INSECURE` is set.
- `options` = `/`-separated `key:value` segments (e.g. `f:opus/br:96`). An *empty* options set is not representable as an empty segment; the minimal always-valid options string is `f:mp3` (the proxy's default format made explicit). This slice treats the options string as opaque input (`raw:`), so the caller provides it pre-rendered.
- `source` = `enc/{base64url(source-string)}` or `plain/{percent-escaped-source-string}`. This gem emits `enc/` only — escaping headaches out of scope by construction.

The proxy's reference signer ships published KAT vectors (key `0011…EEFF`, salt `FFEE…1100`, path `/f:opus/br:96/plain/s3://masters/2026/piece-final.wav` → `zfLTfPPhQ8kdeYYJOdagqPfog2nFk7KzDFUjtRAf_Ns`, and a second vector for `/info/plain/s3://b/k.wav`). These pin the byte contract this gem must honor.

The gem skeleton (gemspec, namespace split, Minitest harness, dummy app) comes from `add-plugin-scaffold`; this change is the first behavior slice. Three follow-ups (`add-options-rendering`, `add-rails-integration`, `add-activestorage-resolution`) build on it.

## Goals / Non-Goals

**Goals:**

- `Audioproxy::Config` with endpoint, key/salt (hex → binary), `unsigned`, `default_options`.
- `Audioproxy::UrlBuilder` producing byte-correct signed URLs from a source string + raw options string.
- `Audioproxy.url_for` as the single public entry point, Rails-free.
- KAT-vector compatibility proven in the test suite.
- Endpoint path-prefix support and per-call `endpoint:` override.

**Non-Goals:**

- Typed option keys, aliases, number formatting (next slice: `add-options-rendering`).
- Railtie, credentials, view helpers (`add-rails-integration`).
- ActiveStorage blob resolution (`add-activestorage-resolution`).
- `plain/` source encoding output (the builder never emits it; KAT fixtures may *contain* `plain/` paths since signing is agnostic to what the path bytes mean).
- `info`/peaks URL helpers, asset-host-style lambda/domain sharding, `blob.representation` hook.

## Decisions

### D1: Everything in this slice is core-namespace only

Per the scaffold slice's namespace split, all code here lives under plain `Audioproxy` with zero Rails/ActiveSupport dependency; nothing touches `Audioproxy::Rails`. The Rails-free load smoke test from the scaffold keeps this honest as behavior arrives.

### D2: Config is a plain mutable singleton with an override path

`Audioproxy.configure { |c| ... }` sets a process-global `Audioproxy::Config` instance (endpoint, key, salt, unsigned, default_options). `url_for` reads the global config but accepts per-call overrides (`endpoint:`, `unsigned:`). Key/salt are supplied as hex strings and decoded to binary eagerly at assignment, raising on odd-length or non-hex input — a bad key should fail at boot, not at first URL. Alternative — decode lazily at signing time — rejected: it turns a config typo into a runtime error in a mailer.

### D3: Signing mirrors the proxy's reference signer exactly

`sign(rest_of_path)` = `Base64.urlsafe_encode64(OpenSSL::HMAC.digest("SHA256", key, salt + rest_of_path), padding: false)`. `rest_of_path` MUST begin with `/` (the builder constructs it that way; the signer raises otherwise, mirroring the proxy's refusal to sign an unverifiable path). No padding, ever — the proxy accepts padded input but the canonical spelling is unpadded, and emitting one spelling keeps URLs cache-stable.

### D4: `enc/` source encoding, unpadded

Source strings are emitted as `enc/` + unpadded base64url. The proxy accepts padded and unpadded `enc/` payloads and both decode to the same source and cache key, but the builder emits exactly one spelling for URL/CDN-cache stability. `plain/` is not emitted (percent-escaping rules — double-escaping already-escaped sources, `+` handling — are a bug farm the `enc/` form exists to avoid).

### D5: Endpoint is a full base URL, joined by string concatenation with trailing-slash normalization

`endpoint` must parse as an absolute `http`/`https` URL and may carry a path prefix. The builder strips at most one trailing `/` from the endpoint and appends `/{signature}{rest_of_path}`. Because the signature covers only `rest_of_path`, a path prefix on the endpoint cannot disturb signing — this is asserted by a dedicated test (same source+options signed under prefixed and unprefixed endpoints produce identical signature segments). No lambda/sharding support.

### D6: `unsigned: true` bypasses key requirements

With `unsigned: true` (config-level or per-call), the signature segment is the literal `insecure` and key/salt may be absent. Signed mode with missing key/salt raises a configuration error naming what is missing. Rationale: dev parity with `AP_ALLOW_INSECURE`, and the failure mode for a misconfigured production app must be loud, not a 403 from the proxy.

### D7: Options input in this slice is `raw:` only

`url_for(source, raw: "f:opus/br:96")` uses the given string verbatim as the options segment. When no options are given and no default options are configured, the builder emits `f:mp3` (the proxy's default format, spelled explicitly) so the path always has an options segment. The raw string is not validated beyond being non-empty without `/` bracketing — the proxy is the validator of option grammar; this gem's typed layer (next slice) will add client-side rendering. Alternative — skip the options segment entirely when empty — rejected: the proxy's path grammar has no optionless form.

### D8: KAT vectors vendored verbatim

The proxy's vector constants (hex key, hex salt, two path→signature pairs) are copied into a fixtures file with a comment naming their origin and the Python generator snippet. The signer test asserts exact equality. If the proxy ever rotates vectors, the fixture comment tells the maintainer where to re-copy from.

## Risks / Trade-offs

- [Global mutable config is process-wide] → Acceptable for MVP (mirrors imgproxy-gem prior art); per-call `endpoint:`/`unsigned:` overrides cover the real multi-instance cases without a config-object plumbing layer.
- [Raw options string is unvalidated client-side] → A typo produces a proxy-side 422, not a client error. Deliberate for this slice; the typed layer narrows this next.
- [Base64 stdlib deprecation churn (`base64` gem un-defaulted in newer Rubies)] → Use `[data].pack`/`String#unpack1` or add `base64` as an explicit dependency; decide in implementation, test on supported Rubies.
- [Endpoint join by concatenation, not URI resolution] → Simple and predictable; a malformed endpoint (no scheme) is rejected at config time rather than producing a relative URL at render time.
