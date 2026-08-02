# audioproxy-rails

Build signed variant URLs for the [audioproxy](https://github.com/audioproxy) media server from a Rails app: point at a source audio file, describe the variant you want (format, bitrate, waveform, …), and get back a URL the proxy will accept.

## Architecture

The URL builder lives in a Rails-free `Audioproxy` namespace — plain Ruby, no Rails constants, so it can be extracted to a standalone gem with a `git mv`. Everything Rails-facing lives under `Audioproxy::Rails` and hooks in through a railtie, not an engine: no routes, no `app/`, no migrations.

Rails is a development dependency only. `require "audioproxy"` works in a plain Ruby process; the railtie is required only when `Rails::Railtie` is already defined.

## Status

Core signing works. Typed options (`f:`, `br:`, `t:` as Ruby keywords), the Railtie and credentials wiring, view helpers, and ActiveStorage blob resolution are follow-up slices; see `openspec/changes/`.

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

`raw:` is a pre-rendered options string used verbatim; the builder supplies the surrounding separators, so do not bracket it with `/`. Set a default for every call with `config.default_options = { raw: "f:opus" }` (string keys work too, so a value read from YAML or ENV behaves the same). With neither, the options segment is `f:mp3` (the proxy's default format spelled out, since its path grammar has no optionless form). Typed option keys land in a follow-up slice.

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
