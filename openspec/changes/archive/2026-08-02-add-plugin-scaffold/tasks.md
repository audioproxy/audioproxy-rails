## 1. Generate

- [x] 1.1 Pin the Rails version and run `rails plugin new audioproxy-rails` (plain form: no `--mountable`, no `--full`, Minitest defaults) into this repository; commit the raw generator output as one commit noting the generating Rails version
- [x] 1.2 Reconcile generator output with existing repo files (`.gitignore`, README stub, license)

## 2. Trim to the settled architecture

- [x] 2.1 Move the version constant to `Audioproxy::VERSION`; establish `lib/audioproxy.rb` as the entry point with core requires under plain `Audioproxy`, keeping `Audioproxy::Rails` for the railtie
- [x] 2.2 Demote Rails to a development dependency in the gemspec; guard the railtie require with `defined?(Rails::Railtie)`
- [x] 2.3 Verify no engine artifacts remain (no `app/`, no routes, no migrations)

## 3. Prove the boundaries

- [x] 3.1 Add the Rails-free load smoke test (`require "audioproxy"` in a plain Ruby process defines `Audioproxy`, not `Rails`)
- [x] 3.2 Add the dummy-app boot test asserting the gem's railtie is registered
- [x] 3.3 `rake test` green
- [x] 3.4 README: replace the generator boilerplate — what the gem is (signed variant URLs for the audioproxy server), the architecture in two sentences (Rails-free `Audioproxy` core, `Audioproxy::Rails` integration layer; railtie, no engine), current status (skeleton; functionality lands in the following changes), and how to run the tests
