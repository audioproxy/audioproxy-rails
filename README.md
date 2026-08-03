# audioproxy-rails

Build signed variant URLs for the [audioproxy](https://github.com/audioproxy) media server from a Rails app: point at a source audio file, describe the variant you want (format, bitrate, waveform, …), and get back a URL the proxy will accept.

## Architecture

`Audioproxy::Signer` holds signature building and depends on stdlib and `base64` only, so it can be lifted into a standalone gem with a `git mv` if a non-Rails project ever needs it. The rest of the `Audioproxy` namespace — configuration and URL assembly — is a Rails integration and uses ActiveSupport. Everything Rails-facing lives under `Audioproxy::Rails` and hooks in through a railtie, not an engine: no routes, no `app/`, no migrations.

Full Rails is a development dependency only. `require "audioproxy"` works in a plain Ruby process; the railtie is required only when `Rails::Railtie` is already defined.

## Status

Core signing and typed options work, in both the proxy's short spellings and their aliases. The Railtie and credentials wiring, view helpers, and ActiveStorage blob resolution are follow-up slices; see `openspec/changes/`.

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

Describe the variant with the proxy's option keys as Ruby keyword arguments, either in the proxy's own short spelling or in the spelled-out alias next to it:

```ruby
Audioproxy.url_for("s3://masters/piece.wav", f: :opus, br: 96, t: [12.5, 30])
# => ".../f:opus/br:96/t:12.5:30/enc/..."
```

| Key | Alias | Example | Meaning |
| --- | --- | --- | --- |
| `f` | `format` | `f: :opus` | output format |
| `br` | `bitrate` | `br: 96` | bitrate (kbps) |
| `q` | `quality` | `q: 5` | quality, for codecs that take one instead of a bitrate |
| `sr` | `sample_rate` | `sr: 44100` | sample rate |
| `ch` | `channels` | `ch: 1` | channel count |
| `bd` | `bit_depth` | `bd: 24` | bit depth |
| `t` | `trim` | `t: [12.5, 30]` | trim: start, optional duration |
| `fade` | `fade` | `fade: [1, 2]` | fade in, optional fade out |
| `gain` | `gain` | `gain: -2.5` | gain adjustment (dB) |
| `norm` | `normalize` | `norm: [:ebu, -16, -1.5, 11]` | loudness normalization: mode, then I, TP, LRA |
| `pts` | `peak_count` | `pts: 800` | peak points, for waveform output |
| `pk_fmt` | `peak_format` | `pk_fmt: :json` | peaks format |
| `dl` | `download` | `dl: "piece.mp3"` | download filename |
| `cb` | `cache_buster` | `cb: "v2"` | cache buster |

Segments render in the order you write the keywords. The gem does not sort them and does not materialize defaults; that is the proxy's normalization, and a half-normalization here would only invent a third spelling. If you want URLs to stay stable across a codebase, keep the argument order stable.

`t`, `fade` and `norm` take colon-separated parts, so they take arrays: `t: [12.5, 30]` renders `t:12.5:30`. A single part can be written as a scalar: `t: 12.5` renders `t:12.5`. Symbols and strings render alike, so `f: :opus` and `f: "opus"` are the same URL.

An unrecognized key (`bt: 96`, or a guessed alias like `bit_rate: 96`) raises `ArgumentError` listing the keys that exist and noting that each is also accepted spelled out. So does a value carrying a character that would break the path: the gem supplies the `/` and `:` separators, so a value containing one would invent a segment or a part, and a `?` or `#` would end the path in a browser, leaving the proxy with less than what was signed (a 403, at request time, nowhere near the call). Whitespace is rejected for the same reason, which means a `dl:` filename with spaces has to be pre-encoded by you; the gem will not invent an encoding, because that would change the bytes it signs.

Value *domains* are not checked: `br: 999999` renders, and the proxy rejects it with a structured 422. Duplicating the proxy's validation rules here would mean two rule sets drifting apart, with a stale client rejecting URLs a newer proxy accepts.

### Both spellings work

Every key has the spelled-out alias in the table above, for call sites that would rather read than decode:

```ruby
Audioproxy.url_for(source, format: :opus, bitrate: 96, sample_rate: 44100)
# => ".../f:opus/br:96/sr:44100/enc/..."
```

An alias resolves to its canonical key before anything is rendered, so the two spellings produce byte-identical URLs and the same cache key. `fade` and `gain` are already words and are their own alias.

The short keys stay first-class rather than becoming a legacy spelling: they are the proxy's own vocabulary, they are what a `raw:` string contains, and they are what the proxy's own error messages name. Mixing the two in one call (`format: :opus, br: 96`) is fine; the gem renders it correctly, and house style is a linting matter.

Giving *both* spellings of one option in a single call raises `ArgumentError` naming both, rather than letting one silently win:

```ruby
Audioproxy.url_for(source, bitrate: 96, br: 128)
# ArgumentError: Audioproxy option br was given twice, as bitrate and br
```

Aliases work in `config.default_options` too, where the same conflict is rejected at assignment, so it fails at boot rather than in a mailer. Resolution happens before the defaults merge, so a default of `bitrate: 96` and a per-call `br: 128` are one key that overrides (`br:128`, in the default's position), not two bitrate segments.

### Seconds can be written as durations

`t` and `fade` are the two keys whose values *are* seconds, so they accept an `ActiveSupport::Duration`:

```ruby
Audioproxy.url_for(source, t: 30.seconds)                   # => ".../t:30/..."
Audioproxy.url_for(source, trim: [12.5, 1.minute])          # => ".../t:12.5:60/..."
Audioproxy.url_for(source, fade: [1.5.seconds, 2.seconds])  # => ".../fade:1.5:2/..."
```

A duration renders exactly as the number of seconds it stands for, so `t: 30.seconds` and `t: 30` are one URL and one cache key. A duration anywhere else raises: `br: 3.seconds` is a bug, and rendering `br:3` from it would be a valid-looking URL for the wrong variant.

The `30.seconds` spelling itself comes from ActiveSupport's time core extensions, which Rails loads for you. In a plain Ruby process that requires only `audioproxy`, `30.seconds` raises `NoMethodError` — this gem accepts a `Duration` but does not patch `Integer` to manufacture one. Either require `active_support/core_ext/numeric/time` yourself, or write `ActiveSupport::Duration.seconds(30)`.

### Numbers have one canonical spelling

The proxy renders numbers minimally and hashes the normalized options string into its cache key. A URL carrying `t:12.50` still works, because the proxy re-normalizes, but it is a second CDN and browser cache entry for a byte-identical variant. So numbers here render the way the proxy renders them:

| You write | It renders |
| --- | --- |
| `t: 30` or `t: 30.0` | `t:30` |
| `gain: -2.50` | `gain:-2.5` |
| `t: 0.125` | `t:0.125` |
| `gain: 0.001` | `gain:0.001`, never `1.0e-03` |
| `gain: -0.0` | `gain:0` |

Integers, floats, rationals and `BigDecimal`s all go through this, and the rendering is exact: a `BigDecimal` keeps digits a double would lose, and a large float renders the decimal you wrote rather than the binary value underneath it. Strings do not go through it at all: a string value is used verbatim, which is how you opt out of formatting.

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
