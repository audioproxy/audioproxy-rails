# Changelog

## 0.3.0

* Probe metadata URLs. `Audioproxy.info_url(source)` and the `audioproxy_info_url` view helper
  build the proxy's `/info` URL, which returns duration, sample rate, channels and tags as JSON. The
  proxy's `/info` has no options segment, so `info_url` raises for any option or `raw:`, and ignores
  `config.default_options` and `config.expires_in`. Info URLs therefore never expire, even when
  every other URL your app builds does.

* Waveform peaks URLs. `Audioproxy.peaks_url(source, **options)` and the `audioproxy_peaks_url`
  view helper build a variant URL with `f:peaks` fixed. They accept only the options that change a
  waveform (`pts`, `pk_fmt`, `pk_bits`, `ch`, `t`, `fade`, `gain`, `norm`, `dl`, `cb`) and raise on
  the rest, since the proxy refuses encoding options on peaks. Of the configured defaults, only
  `t`, `fade`, `gain`, `norm` and `cb` carry over, so the waveform follows normalized audio while an
  audio default such as `br: 96` or `ch: 2` never reaches a peaks request.

* `pk_bits` option, aliased as `peak_bits`: the width of each peaks value, 8 or 16. peaks.js reads
  only 8-bit data, so a peaks.js client asks for `pk_bits: 8`. Requires audioproxy 0.8.0 or newer;
  older proxies answer `pk_bits:` with a `422`.

* `url_for` output is unchanged, byte for byte.

## 0.2.0

* Expiring URLs. `url_for` and every view helper accept `expires_in:` (a duration or Integer
  seconds from now) and `expires_at:` (the instant itself), mutually exclusive, rendering the
  proxy's `exp:` option. `config.expires_in` sets a global default; a per-call `expires_in: nil`
  opts one URL out of it.

  Because `exp` is a request option on the proxy rather than a variant option, it is signed but
  excluded from the cache key: minting a fresh short-lived URL on every render costs no extra
  render and no extra cached variant at the origin.

  Every input that would produce a valid-looking URL the proxy refuses raises at the call site
  instead: both keywords together, a non-positive window, an `expires_at` at or before now, a
  fractional duration, a millisecond timestamp, a `Date`, and `exp:` written as a plain option key
  or in `default_options`.

  Requires audioproxy 0.6.0 or newer, the release that added the `exp` option. Older proxies
  answer `exp:` with a `422`. Every other feature in this gem still works against 0.5.0.

* `Audioproxy::Signer` is unchanged, and so is the isolation test that pins its extraction seam:
  `exp` is ordinary path bytes to the signer.

## 0.1.0

First release.

* Signed URL building for the audioproxy server. `Audioproxy::Signer` reproduces the server's
  signature byte for byte, and is checked against the server's published known-answer vectors
  rather than against this gem's own output.

* Typed variant options, in both the proxy's short spellings and their aliases. Malformed options,
  a `nil` source, and an endpoint carrying credentials or a query raise at configuration or call
  time instead of producing a URL that looks valid and is refused by the proxy later.

* Configuration through Rails credentials or ENV, wired by a railtie. The gem contributes no
  routes, no migrations, and no `app/` directory.

* View helpers: `audioproxy_url`, `audioproxy_audio_tag`, and `audioproxy_preload_link_tag`.
  Proxy options and HTML attributes stay in separate namespaces, and all three render the same
  bytes for the same inputs.

* ActiveStorage resolution for the S3 and Disk services. A blob on any other service raises with
  the service named, rather than guessing at a public URL.

`Audioproxy::Signer` depends on stdlib and `base64` only, with no ActiveSupport and no other file
in this gem, so signature building can be lifted into a standalone gem if a non-Rails project ever
needs it.
