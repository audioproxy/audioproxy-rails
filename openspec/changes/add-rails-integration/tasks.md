## 1. Railtie

- [ ] 1.1 Implement config sourcing in the scaffolded `Audioproxy::Rails::Railtie`: ENV (`AP_ENDPOINT`/`AP_KEY`/`AP_SALT`/`AP_ALLOW_INSECURE`) overlaid by credentials `audioproxy.{endpoint,key,salt,unsigned}`, per-attribute, assigning only what is present, no boot-time validation
- [ ] 1.2 Wire the dummy app (`test/dummy`) for credential/ENV test fixtures
- [ ] 1.3 Tests: credentials sourcing (string and symbol keys), ENV fallback per attribute, credentials-beat-ENV, initializer override wins, empty boot succeeds and later signed `url_for` raises the core error

## 2. View helpers

- [ ] 2.1 Implement `Audioproxy::Rails::Helpers` with `audioproxy_url` and `audioproxy_audio_tag(source, **opts, html: {})`; mix in via `ActiveSupport.on_load(:action_view)`
- [ ] 2.2 Tests (`ActionView::TestCase` level): `audioproxy_url` delegation, `audio_tag` output with `html:` attributes, proxy options never appear as tag attributes

## 3. Wrap-up

- [ ] 3.1 README: Rails setup section — credentials example (`audioproxy.{endpoint,key,salt}`), ENV parity note (shared env file with the proxy in dev, `AP_ALLOW_INSECURE` caveat: never in production), configuration precedence (initializer > credentials > ENV), `audioproxy_url` and `audioproxy_audio_tag` usage including the `html:` seam and why proxy options never become tag attributes
- [ ] 3.2 Full suite green with and without Rails loaded (verify core tests still pass standalone)
