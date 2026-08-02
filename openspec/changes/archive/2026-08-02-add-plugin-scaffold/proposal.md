## Why

Every following slice needs a gem skeleton to land in. Rather than hand-rolling gemspec, test harness, and railtie boilerplate, `rails plugin new` generates the canonical Rails-plugin shape — railtie, dummy app for integration tests, Minitest wiring — which is exactly the "railtie, no engine" form the gem is settled on. Scaffolding is its own slice so the generated-versus-authored boundary is one reviewable commit.

## What Changes

- Scaffold the repository with `rails plugin new` (plain plugin: no `--mountable`, no `--full` — a railtie, not an engine; no routes, views, or migrations).
- Trim the generated skeleton to match the settled architecture:
  - Top-level namespace is `Audioproxy` (the generator's hyphen-derived `Audioproxy::Rails` nesting is kept only for the Rails-facing layer; core files live in `lib/audioproxy/` under plain `Audioproxy`).
  - Rails moves from runtime to **development dependency**; the railtie require in `lib/audioproxy.rb` is guarded by `defined?(Rails::Railtie)` so the gem loads Rails-free. The Rails-free core arrives in `add-gem-core-signing`; this slice just keeps the door open.
  - Keep the generated dummy app (`test/dummy`) as the integration-test harness for the later Rails slices; keep Minitest.
- Empty railtie shell stays in place; `add-rails-integration` fills it in.
- CI-runnable `bin/test` / `rake test` green on the generated suite.

## Capabilities

### New Capabilities

- `gem-packaging`: what the packaged gem guarantees — name, namespace layout, Rails-free loadability, railtie presence under Rails, test harness shape.

### Modified Capabilities

_None — greenfield repository._

## Impact

- New files: everything `rails plugin new` generates (gemspec, `lib/`, `test/dummy`, `Rakefile`, `Gemfile`), minus trimmed engine-isms, plus the dependency demotion and guarded require.
- Downstream: `add-gem-core-signing`, `add-options-rendering`, `add-rails-integration`, `add-activestorage-resolution` all build on this skeleton.
