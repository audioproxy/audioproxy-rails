# audioproxy-rails

Build signed variant URLs for the [audioproxy](https://github.com/audioproxy) media server from a Rails app: point at a source audio file, describe the variant you want (format, bitrate, waveform, …), and get back a URL the proxy will accept.

## Architecture

`Audioproxy::Signer` holds signature building and depends on stdlib and `base64` only, so it can be lifted into a standalone gem with a `git mv` if a non-Rails project ever needs it. The rest of the `Audioproxy` namespace — configuration and URL assembly — is a Rails integration and uses ActiveSupport. Everything Rails-facing lives under `Audioproxy::Rails` and hooks in through a railtie, not an engine: no routes, no `app/`, no migrations.

Full Rails is a development dependency only. `require "audioproxy"` works in a plain Ruby process; the railtie is required only when `Rails::Railtie` is already defined.

## Status

Core signing and typed options work, in both the proxy's short spellings and their aliases, as do the Railtie's credentials/ENV wiring, the view helpers — URL, `<audio>` tag and preload hint — and ActiveStorage resolution for the S3 and Disk services. Blobs on any other service raise; see [ActiveStorage](#activestorage) for what to do about that.

## Installation

```ruby
gem "audioproxy-rails"
```

## Quick start

Tell the gem where the proxy lives:

```yaml
# bin/rails credentials:edit
audioproxy:
  endpoint: https://audio.example.com
  key: 7a3f9c21…      # hex, from the proxy's AP_KEY
  salt: 9c217a3f…     # hex, from the proxy's AP_SALT
```

Then hand a view an ActiveStorage attachment:

```erb
<%= audioproxy_audio_tag @recording.audio,
      format: "opus", bitrate: 96,
      html: { controls: true } %>
```

```html
<audio controls="controls"
       src="https://audio.example.com/zfLTfPPh…/f:opus/br:96/enc/bG9jYWw6Ly93eC95ei93…"></audio>
```

That is the whole path. `@recording.audio` is an ordinary `has_one_attached`; the gem reads the storage service the blob lives on, turns it into the source string the proxy speaks (`s3://…` or `local://…`), renders the variant you asked for, and signs the result. The view helpers arrive through a railtie, so there is nothing to include and nothing to mount.

Blobs, attachments and `has_one_attached` associations all work, and so does a plain source string if you are not using ActiveStorage:

```ruby
Audioproxy.url_for("s3://masters/2026/piece-final.wav", format: "opus", bitrate: 96)
```

Where to go from here:

- [Options](#options) for the full variant vocabulary, in the proxy's short keys or their spelled-out aliases.
- [ActiveStorage](#activestorage) for which storage services are supported, and for the one deployment coupling disk storage brings with it.
- [Rails](#rails) for configuration precedence across credentials, ENV and an initializer.
- `config.unsigned = true` for development against a proxy running `AP_ALLOW_INSECURE`, where no key or salt is needed.

## Configuration

```ruby
Audioproxy.configure do |config|
  config.endpoint = "https://audio.example.com"   # absolute http(s) URL, path prefix allowed
  config.key      = ENV["AP_KEY"]                 # hex string, decoded at assignment
  config.salt     = ENV["AP_SALT"]                # hex string, decoded at assignment
end
```

Writing this out is optional. Under Rails the railtie already reads `audioproxy:` from credentials
and `AP_ENDPOINT`, `AP_KEY`, `AP_SALT` and `AP_ALLOW_INSECURE` from the environment, so an app that
uses either needs no initializer at all; see [ENV parity with the proxy](#env-parity-with-the-proxy)
and [Rails](#rails). Configure by hand when you want to override those, or when there is no Rails.

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
Audioproxy.url_for(source, raw: "f:opus", br: 96)        # ArgumentError
Audioproxy.url_for(source, raw: "f:opus", bitrate: 96)   # ArgumentError — an alias is a typed key
```

`config.default_options` applies to every call. Typed defaults merge under typed per-call keys, key by key:

```ruby
Audioproxy.configure { |c| c.default_options = { f: :opus, br: 96 } }

Audioproxy.url_for(source, br: 128)   # => .../f:opus/br:128/...
```

A per-call `raw:` replaces the defaults entirely, and so do per-call typed keys when the default is a `raw:` string — in either vocabulary, since an alias counts as a typed key everywhere `raw:` and typed keys are mutually exclusive. Putting `raw:` and typed keys in `default_options` together raises at configuration time. String keys work throughout, so a value read from YAML or ENV behaves the same. With no options and no defaults, the segment is `f:mp3`, the proxy's default format spelled out, because its path grammar has no optionless form.

## Per-call overrides

Per call you can override the endpoint (for a second proxy instance or another region) and the unsigned flag, without touching the global config:

```ruby
Audioproxy.url_for("local://a.wav", endpoint: "https://audio-eu.example.com")
Audioproxy.url_for("local://a.wav", unsigned: true)
```

`Audioproxy.url_for` is Rails-free: it works in jobs, mailers, serializers, and plain Ruby scripts.

## Rails

In a Rails app there is nothing to mount and, usually, nothing to write: a railtie reads your configuration and mixes the view helpers into ActionView.

### Configuration from credentials

```bash
bin/rails credentials:edit
```

```yaml
audioproxy:
  endpoint: https://audio.example.com
  key: 00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff
  salt: ffeeddccbbaa99887766554433221100
```

That is the whole setup. String and symbol keys both work, and each setting resolves on its own — you can keep `key` and `salt` in credentials and leave `endpoint` to the environment.

### ENV parity with the proxy

Every setting also reads from an environment variable, and the names are the proxy's own:

| Setting | Variable |
| --- | --- |
| `endpoint` | `AP_ENDPOINT` |
| `key` | `AP_KEY` |
| `salt` | `AP_SALT` |
| `unsigned` | `AP_ALLOW_INSECURE` |

The names match on purpose: in development you can point a docker-compose app service and the proxy service at one shared env file and have both read the same values. An empty variable (`AP_KEY=` with nothing after it) counts as unset.

`AP_ALLOW_INSECURE` accepts `1`, `t`, `true`, `0`, `f`, `false`, case-insensitively, and raises on anything else. Those are the literals Go's `strconv.ParseBool` accepts, which is what the proxy parses the variable with — the case-insensitivity is the one liberty taken, so `True` and `TrUe` both work here where Go takes only the former. It is stricter than Rails' usual boolean cast for a reason: a cast that reads every unrecognized string as true would turn `AP_ALLOW_INSECURE=flase` into a production app emitting unsigned URLs.

In credentials the same setting takes a YAML boolean, or an unquoted `1`/`0`, which YAML hands over as an Integer. Anything under `audioproxy:` that is not `endpoint`, `key`, `salt` or `unsigned` raises, and so does one setting written twice under different spellings. That strictness earns its keep on `unsigned` in particular: the other three default to nothing and would fail loudly at `url_for`, but `unsinged: true` would leave `unsigned` at `false` and quietly emit a signed URL where you meant the `insecure` segment.

Two caveats on that flag. It sets only *this* client's behaviour, telling the gem to emit the literal `insecure` signature segment instead of an HMAC; the proxy decides independently whether it will accept one. And it belongs in development only — never set it in production, where it hands anyone who can read a URL the ability to request any variant of any source.

### Precedence

**initializer > credentials > ENV.** The railtie reads ENV first, lays credentials over it per setting, and app initializers run afterwards, so an explicit `Audioproxy.configure` in `config/initializers/audioproxy.rb` always has the last word:

```ruby
# config/initializers/audioproxy.rb — wins over credentials and ENV
Audioproxy.configure do |config|
  config.endpoint = "https://audio-staging.example.com"
  config.default_options = { format: "opus", bitrate: 96 }
end
```

Nothing is validated at boot. An app with no credentials and no ENV boots fine — a signed `url_for` is where the missing key surfaces, and an app running unsigned in development never needs one. That keeps `assets:precompile` and similar tasks working in apps that never generate a URL. It also means URL generation belongs at request or job time, not at class-load time in a constant.

### View helpers

`audioproxy_url` is `Audioproxy.url_for` under another name, available in every view:

```erb
<%= audioproxy_url(@track.master_url, format: "opus", bitrate: 96) %>
```

`audioproxy_audio_tag` builds that URL and hands it to Rails' `audio_tag`. Proxy options are keyword arguments; HTML attributes go in `html:`:

```erb
<%= audioproxy_audio_tag @track.master_url,
      format: "opus", bitrate: 96,
      html: { controls: true, preload: "none", class: "player" } %>
```

```html
<audio controls="controls" preload="none" class="player"
       src="https://audio.example.com/zfLTfPPh…/f:opus/br:96/enc/…"></audio>
```

The `html:` bucket is not ceremony. Without it, proxy option names and HTML attribute names would share one namespace, and the gem would have to guess which one you meant for any key it did not recognize — so a mistyped `bitrat: 96` would land silently on the `<audio>` element as an attribute and quietly ship the default format instead. With the bucket, the two never mix in either direction: an unknown proxy option raises, and an `html:` entry never reaches the proxy. Proxy options never appear as tag attributes.

#### Preloading a variant

`audioproxy_preload_link_tag` emits a resource hint for a variant you are about to play. Because the first request for a variant is a render, the hint overlaps that render with page load rather than leaving someone waiting for it after a click:

```erb
<% opus = { format: "opus", bitrate: 96 } %>

<%# in a layout that yields :head, or wherever your <head> content goes %>
<% content_for :head do %>
  <%= audioproxy_preload_link_tag @track.audio, **opus, html: { fetchpriority: "high" } %>
<% end %>

<%= audioproxy_audio_tag @track.audio, **opus, html: { controls: true } %>
```

```html
<link rel="preload" href="https://audio.example.com/zfLTfPPh…/f:opus/br:96/enc/…" as="audio" fetchpriority="high">
```

The shared local is the point. The hint and the element have to name the same variant, byte for byte: one differing option is a different URL, a different cache key, and a preload the browser never matches to the `<audio>` element that needed it. Writing the options out twice is how that goes wrong.

`as="audio"` is supplied for you. Rails infers `as` from a file extension, and a proxy URL ends in an encoded source segment that has none, so the inference cannot work here — and a `rel=preload` carrying no `as` has no fetch destination, which browsers decline to act on. Pass `html: { as: … }` if you need something else; a blank one (`nil`, `false`, `""`) raises rather than quietly producing that inert tag.

Three things worth knowing before reaching for it:

- **It fetches the whole variant.** On a cache miss the proxy answers chunked with no `Accept-Ranges`, so there is no partial preload to be had. This is a hint for the track that is about to play, not for a list of forty.
- **`crossorigin` must match the element.** Neither helper sets one, so by default they agree. If you add `crossorigin` to the `<audio>` tag, add the same value here, or the browser treats them as two different requests and downloads the variant twice. Write it as a string: Rails renders `crossorigin: true` as `anonymous` on a preload link and as `true` on an `<audio>` tag, so the boolean would produce exactly that mismatch — this helper raises on it rather than letting it through.
- **Rails also emits a `Link` header** for every preload when `config.action_view.preload_links_header` is on — another reason to preload one track rather than a page of them.

### ActiveStorage

Anywhere a source string is accepted, an ActiveStorage blob, an attachment, or a `has_one_attached` association works instead:

```erb
<%= audioproxy_audio_tag @recording.audio, format: "opus", bitrate: 96 %>
```

```ruby
Audioproxy.url_for(recording.audio)        # has_one_attached
Audioproxy.url_for(recording.audio.blob)   # the blob itself
```

The blob is turned into a source string by looking at the storage service it lives on — the service class, not the name you gave it in `storage.yml`, since `:local` and `:amazon` are labels an app is free to hang on anything.

| Service | Source string | Status |
| --- | --- | --- |
| `S3Service` | `s3://{bucket}/{key}`, bucket read off the service | Supported |
| `DiskService` | `local://{key[0..1]}/{key[2..3]}/{key}` | Supported, with the deployment coupling below |
| Anything else — GCS, Azure, Mirror | — | Raises `Audioproxy::UnsupportedServiceError` |

An app's own subclass of a supported service resolves the way its parent does. A Mirror service is *not* unwrapped to its primary, even when that primary is S3: which copy the proxy should read is a deployment decision, so the error names the mirror and leaves the choice to you rather than guessing. Point the blob at the primary service directly if that is what you meant.

Asking for a URL for an empty attachment raises `Audioproxy::UnattachedError` naming the attachment, rather than emitting a URL that would 404 at the proxy.

#### Disk storage couples `AP_LOCAL_ROOT` to your storage root

For `local://` sources, the proxy resolves the path against its own `AP_LOCAL_ROOT`. So **the proxy's `AP_LOCAL_ROOT` must be the same directory as the Disk service's `root`** in `config/storage.yml` — the same volume mounted into both, in a container deployment:

```yaml
# config/storage.yml
local:
  service: Disk
  root: /var/audio
```

```bash
# the proxy
AP_LOCAL_ROOT=/var/audio
```

If they disagree, URLs generate fine and the proxy answers 404. The gem cannot check this and does not try: it has no way to see the proxy's environment.

This coupling is not avoidable by pointing the proxy at your app instead. ActiveStorage's ordinary disk URLs are Rails routes that redirect to the file, and the proxy's HTTPS source backend refuses redirects by design.

The two hashed subdirectories in the path are ActiveStorage's own layout for disk storage (`DiskService#path_for`), reproduced here because the proxy needs a path rather than an ActiveStorage lookup. It is the one piece of near-private Rails API this gem leans on, so it lives alone in `Audioproxy::Rails::BlobResolver::DiskLayout`, with a test that pins it against the real `DiskService` in both directions: identical paths for every key the service accepts, and an error for every key it rejects. A Rails upgrade that changed the layout fails the suite rather than silently generating 404s.

Blob keys carrying a `.` or `..` path segment, or a null byte, raise. `DiskService` refuses them as path-traversal defense, and this side has more reason to: it never touches a filesystem, so nothing downstream would catch a key that walks out of the storage root. Keys ActiveStorage generates itself never look like this; explicitly-set keys can. Note that the S3 path does *not* apply the same rule, deliberately — an S3 key is an opaque string in which `..` means nothing, and `S3Service` does not reject it either.

#### Other services: the third rung

GCS, Azure and the rest have no proxy-side counterpart today. The general-purpose answer is ActiveStorage's `rails_storage_proxy` mode — proxied URLs stream the file back with a `200` instead of redirecting — served to the proxy through an `https://` source. That source backend is parked upstream on demand, and this gem is the demand signal for it: if you hit `Audioproxy::UnsupportedServiceError`, say so on the proxy's issue tracker, because you are the person that slice is waiting for.

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
