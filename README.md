# audioproxy-rails

Build signed variant URLs for the [audioproxy](https://github.com/audioproxy) media server from a Rails app: point at a source audio file, describe the variant you want (format, bitrate, waveform, …), and get back a URL the proxy will accept.

## Architecture

`Audioproxy::Signer` holds signature building and depends on stdlib and `base64` only, so it can be lifted into a standalone gem with a `git mv` if a non-Rails project ever needs it. The rest of the `Audioproxy` namespace — configuration and URL assembly — is a Rails integration and uses ActiveSupport. Everything Rails-facing lives under `Audioproxy::Rails` and hooks in through a railtie, not an engine: no routes, no `app/`, no migrations.

Full Rails is a development dependency only. `require "audioproxy"` works in a plain Ruby process; the railtie is required only when `Rails::Railtie` is already defined.

## Status

Core signing and typed options work. The Railtie and credentials wiring, view helpers, and ActiveStorage blob resolution are follow-up slices; see `openspec/changes/`.

## Installation

```ruby
gem "audioproxy-rails"
```

## Configuration

```ruby
Audioproxy.configure do |config|
  config.endpoint = "https://audio.example.com"   # absolute http(s) URL, path prefix allowed
  config.key      = ENV["AUDIOPROXY_KEY"]         # hex string, decoded at assignment
  config.salt     = ENV["AUDIOPROXY_SALT"]        # hex string, decoded at assignment
end
```

`key` and `salt` are hex strings, validated eagerly: a typo raises `ArgumentError` at boot rather than in a mailer six hours later. The endpoint must be an absolute `http`/`https` URL. A path prefix (`https://cdn.example.com/audio`, for a CDN routing that prefix to the proxy) is supported and does not disturb signing, because the signature covers only the path after the signature segment. Userinfo, a query and a fragment are rejected: a base URL is scheme, host and optional path prefix, and `https://user:pass@host` would put credentials into every URL you generate.

The gem is deliberately strict about input, because the alternative is not an exception but a 403 from the proxy at request time, far from the call that caused it. A `nil` or non-String source, a `default_options` value that is not a Hash, an unrecognized option key, and a `raw:` string bracketed by `/` all raise.

In development, `config.unsigned = true` emits the literal `insecure` signature segment instead of an HMAC, matching the proxy's `AP_ALLOW_INSECURE` mode. No key or salt is needed in that mode.

## Generating URLs

```ruby
Audioproxy.url_for("s3://masters/2026/piece-final.wav", raw: "f:opus/br:96")
# => "https://audio.example.com/zfLTfPPh…/f:opus/br:96/enc/czM6Ly9tYXN0ZXJz…"
```

The result is `{endpoint}/{signature}/{options}/{source}`. The source is always emitted in `enc/` form (unpadded base64url), so spaces, nested URLs, and already-escaped bytes need no special handling.

## Options

Describe the variant with the proxy's option keys as Ruby keyword arguments:

```ruby
Audioproxy.url_for("s3://masters/piece.wav", f: :opus, br: 96, t: [12.5, 30])
# => ".../f:opus/br:96/t:12.5:30/enc/..."
```

| Key | Example | Meaning |
| --- | --- | --- |
| `f` | `f: :opus` | output format |
| `br` | `br: 96` | bitrate (kbps) |
| `q` | `q: 5` | quality, for codecs that take one instead of a bitrate |
| `sr` | `sr: 44100` | sample rate |
| `ch` | `ch: 1` | channel count |
| `bd` | `bd: 24` | bit depth |
| `t` | `t: [12.5, 30]` | trim: start, optional duration |
| `fade` | `fade: [1, 2]` | fade in, optional fade out |
| `gain` | `gain: -2.5` | gain adjustment (dB) |
| `norm` | `norm: [:ebu, -16, -1.5, 11]` | loudness normalization: mode, then I, TP, LRA |
| `pts` | `pts: 800` | peak points, for waveform output |
| `pk_fmt` | `pk_fmt: :json` | peaks format |
| `dl` | `dl: "piece.mp3"` | download filename |
| `cb` | `cb: "v2"` | cache buster |

Segments render in the order you write the keywords. The gem does not sort them and does not materialize defaults; that is the proxy's normalization, and a half-normalization here would only invent a third spelling. If you want URLs to stay stable across a codebase, keep the argument order stable.

`t`, `fade` and `norm` take colon-separated parts, so they take arrays: `t: [12.5, 30]` renders `t:12.5:30`. A single part can be written as a scalar: `t: 12.5` renders `t:12.5`. Symbols and strings render alike, so `f: :opus` and `f: "opus"` are the same URL.

An unrecognized key (`bt: 96`) raises `ArgumentError` listing the keys that exist. Value *domains* are not checked: `br: 999999` renders, and the proxy rejects it with a structured 422. Duplicating the proxy's validation rules here would mean two rule sets drifting apart, with a stale client rejecting URLs a newer proxy accepts.

### Numbers have one canonical spelling

The proxy renders numbers minimally and hashes the normalized options string into its cache key. A URL carrying `t:12.50` still works, because the proxy re-normalizes, but it is a second CDN and browser cache entry for a byte-identical variant. So numbers here render the way the proxy renders them:

| You write | It renders |
| --- | --- |
| `t: 30` or `t: 30.0` | `t:30` |
| `gain: -2.50` | `gain:-2.5` |
| `t: 0.125` | `t:0.125` |
| `gain: 0.001` | `gain:0.001`, never `1.0e-03` |
| `gain: -0.0` | `gain:0` |

Integers, floats, rationals and `BigDecimal`s all go through this. Strings do not: a string value is used verbatim, which is how you opt out of formatting.

The proxy caps decimals at three places and rejects the rest with `:excessive_precision` rather than rounding, so this gem does the same:

```ruby
Audioproxy.url_for(source, t: 0.1234)   # ArgumentError, at the call site
Audioproxy.url_for(source, t: 0.1 + 0.2)  # ArgumentError: float drift is 0.30000000000000004
```

Round explicitly where the number is computed (`t: (0.1 + 0.2).round(3)`) so the rounding is a decision in your code rather than a silent one in a URL builder.

### `raw:` and defaults

`raw:` is a pre-rendered options string used verbatim, the escape hatch for a proxy option this gem's key table does not know yet. The builder supplies the surrounding separators, so do not bracket it with `/`. Passing `raw:` together with typed keys raises `ArgumentError`: two sources of truth for one segment is ambiguity, not composition.

```ruby
Audioproxy.url_for(source, raw: "f:opus/t:12.5:30")
Audioproxy.url_for(source, raw: "f:opus", br: 96)   # ArgumentError
```

`config.default_options` applies to every call. Typed defaults merge under typed per-call keys, key by key:

```ruby
Audioproxy.configure { |c| c.default_options = { f: :opus, br: 96 } }

Audioproxy.url_for(source, br: 128)   # => .../f:opus/br:128/...
```

A per-call `raw:` replaces the defaults entirely, and so do per-call typed keys when the default is a `raw:` string; mixing the two spellings within `default_options` itself raises at configuration time. String keys work throughout, so a value read from YAML or ENV behaves the same. With no options and no defaults, the segment is `f:mp3`, the proxy's default format spelled out, because its path grammar has no optionless form.

## Per-call overrides

Per call you can override the endpoint (for a second proxy instance or another region) and the unsigned flag, without touching the global config:

```ruby
Audioproxy.url_for("local://a.wav", endpoint: "https://audio-eu.example.com")
Audioproxy.url_for("local://a.wav", unsigned: true)
```

`Audioproxy.url_for` is Rails-free: it works in jobs, mailers, serializers, and plain Ruby scripts.

## Development

Run the test suite with:

```bash
bin/test
```

It boots the dummy Rails app in `test/dummy` for the integration tests. Style checks:

```bash
bin/rubocop
```

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
