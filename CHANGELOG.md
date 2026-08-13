# Changelog

## Unreleased

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

  Requires a proxy build carrying the `exp` option, which is merged upstream but not yet in a
  tagged release. Older proxies answer `exp:` with a `422`.

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
