## Why

The core builder works in any Ruby program, but a Rails app should not have to hand-wire configuration or helpers: credentials should feed the config automatically, and views should have `audioproxy_url` / `audioproxy_audio_tag` available without setup. This slice makes the gem feel native in Rails while keeping the core Rails-free.

## What Changes

- The railtie shell scaffolded in `add-plugin-scaffold` gains its real behavior (still no engine — nothing to mount: no routes, views, or migrations):
  - loads configuration from Rails credentials (`audioproxy.key`, `audioproxy.salt`, `audioproxy.endpoint`, `audioproxy.unsigned`), with ENV fallback (`AP_KEY` / `AP_SALT` / `AP_ENDPOINT` — parity with the proxy's own variable names);
  - mixes the view helpers into ActionView.
- New `audioproxy_url(source, **opts)` view helper delegating to `Audioproxy.url_for`.
- New `audioproxy_audio_tag(source, **opts, html: {})` view helper: builds the URL, then delegates to Rails' `audio_tag` with the `html:` hash as tag options.
- Explicit `Audioproxy.configure` in an initializer always wins over credentials/ENV.
- No ActiveStorage integration in this slice (that is `add-activestorage-resolution`), and no `blob.representation` transparency hook at all (known rabbit hole, revisit on demand).

## Capabilities

### New Capabilities

- `rails-config`: Railtie configuration sourcing — credentials, ENV fallback, precedence rules.
- `view-helpers`: `audioproxy_url` and `audioproxy_audio_tag` in ActionView.

### Modified Capabilities

_None._

## Impact

- Changed code: the scaffolded railtie under `Audioproxy::Rails` gains config sourcing; new `Audioproxy::Rails::Helpers` mixed into ActionView. The conditional railtie require and dev-only Rails dependency are already in place from the scaffold slice.
- Test infrastructure: the scaffold's `test/dummy` app hosts the boot/credential tests; helper tests at `ActionView::TestCase` level.
- Depends on: `add-plugin-scaffold`, `add-gem-core-signing` (and benefits from `add-options-rendering` for typed options in helpers, but does not require it).
