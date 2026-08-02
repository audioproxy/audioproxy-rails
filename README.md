# audioproxy-rails

Build signed variant URLs for the [audioproxy](https://github.com/audioproxy) media server from a Rails app: point at a source audio file, describe the variant you want (format, bitrate, waveform, …), and get back a URL the proxy will accept.

## Architecture

The URL builder lives in a Rails-free `Audioproxy` namespace — plain Ruby, no Rails constants, so it can be extracted to a standalone gem with a `git mv`. Everything Rails-facing lives under `Audioproxy::Rails` and hooks in through a railtie, not an engine: no routes, no `app/`, no migrations.

Rails is a development dependency only. `require "audioproxy"` works in a plain Ruby process; the railtie is required only when `Rails::Railtie` is already defined.

## Status

Skeleton. This repository currently contains the packaging, the namespace split, and the tests that pin those boundaries — no signing or URL-building functionality yet. That lands in the following changes (see `openspec/changes/`).

## Installation

```ruby
gem "audioproxy-rails"
```

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
