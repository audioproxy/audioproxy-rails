## Context

Greenfield repo (only `openspec/` and tool config exist). The settled architecture: one unified gem `audioproxy-rails`; builder in a Rails-free `Audioproxy` namespace so a pure-Ruby extraction stays a later `git mv`; a Railtie, not an engine; Minitest.

`rails plugin new` (plain form) generates: gemspec with Rails as a runtime dependency, `lib/audioproxy/rails.rb` + `railtie.rb` + `version.rb` under `Audioproxy::Rails` (hyphenated name → nested modules), a `test/dummy` Rails app, Minitest wiring, `bin/test`. Two of those defaults conflict with the settled architecture and get trimmed here.

## Goals / Non-Goals

**Goals:**

- Generated skeleton committed as one recognizable unit, then trimmed in clearly-authored commits.
- Gem loads without Rails; railtie activates under Rails.
- Dummy app + Minitest harness ready for the later Rails slices.

**Non-Goals:**

- Any actual functionality: no config, no signing, no helpers (those are the following slices).
- Engine features (`--mountable`/`--full`): no routes, no `app/`, no migrations, no isolate_namespace.
- CI pipeline definition beyond a green local `rake test` (CI service wiring can ride along with any later slice).

## Decisions

### D1: Plain `rails plugin new audioproxy-rails`, then trim — not hand-rolled, not `bundle gem`

The plugin generator is the only one that ships the dummy-app harness and railtie shape we want; `bundle gem` would mean hand-building both. Generate with defaults (Minitest is the default), skip nothing structural, and do the trimming as explicit follow-up commits so the diff against "what the generator gave us" stays auditable.

### D2: Namespace split — `Audioproxy` core, `Audioproxy::Rails` integration layer

The generator derives `Audioproxy::Rails` from the hyphenated gem name. Keep that module for the Rails-facing layer (railtie now; helpers and blob resolver in later slices), and reserve plain `Audioproxy` (`lib/audioproxy.rb`, `lib/audioproxy/*.rb`) for the Rails-free core. `version.rb` moves to `Audioproxy::VERSION`. This is the `git mv`-extraction seam: core files never mention `::Rails`.

### D3: Rails becomes a development dependency; railtie require is guarded

The generated gemspec's `spec.add_dependency "rails"` becomes a development dependency, and `lib/audioproxy.rb` requires the railtie only `if defined?(Rails::Railtie)`. A Rails-free smoke test (`ruby -Ilib -e "require 'audioproxy'"`) pins this from day one, before the core even has behavior worth testing.

### D4: Keep `test/dummy` even though this slice barely uses it

The dummy app is the integration harness `add-rails-integration` and `add-activestorage-resolution` need; deleting it now to re-generate later is churn. One boot test (dummy app initializes, gem's railtie is in `Rails.application.railties`) keeps it from bit-rotting unexercised.

## Risks / Trade-offs

- [Generator output varies across Rails versions] → Pin the Rails version in the Gemfile before generating; note the generating version in the scaffold commit message.
- [Dummy app drags Rails into every `rake test` run] → Acceptable: core tests stay runnable standalone via plain Minitest file runs; the Rails-free load test guards the boundary that matters.
- [Trimming generated files invites drift from Rails conventions] → Trim minimally (dependency line, require guard, namespace of core files); leave everything else generator-shaped.
