## 1. Helper

- [ ] 1.1 Add `audioproxy_preload_link_tag(source, html: {}, **options)` to `Audioproxy::Rails::Helpers`, delegating to ActionView's `preload_link_tag` (D1)
- [ ] 1.2 Reject a non-Hash `html:` with the same `ArgumentError` shape `audioproxy_audio_tag` uses (D4)
- [ ] 1.3 Default `as: "audio"`, overridable from `html:`, with a comment recording why inference cannot work here (D2)
- [ ] 1.4 Set no `crossorigin`; record the pairing rule in a comment so a later reader does not "improve" it to `anonymous` (D3)

## 2. Tests

- [ ] 2.1 Tag shape: `rel="preload"`, `as="audio"`, `href` is the proxy URL
- [ ] 2.2 `html:` attributes render; `as:` in `html:` overrides the default and does not produce a duplicate attribute
- [ ] 2.3 No `crossorigin` unless asked for
- [ ] 2.4 Proxy options never render as attributes; an unknown proxy option raises rather than becoming one
- [ ] 2.5 Non-Hash `html:` raises
- [ ] 2.6 Attachment and blob sources resolve through the helper
- [ ] 2.7 `href` is byte-identical to `audioproxy_audio_tag`'s `src` for the same arguments (D5)
- [ ] 2.8 Endpoint path prefix survives: assert `href` equals `audioproxy_url` exactly, proving `path_to_asset` does not rewrite an absolute URL (D5)
- [ ] 2.9 Add the same byte-identity assertion for `audioproxy_audio_tag`, which has never had one (D5)

## 3. Docs

- [ ] 3.1 README: preload subsection under View helpers, with an example showing the hint and the `<audio>` tag sharing one local so drift is visible
- [ ] 3.2 README: the three caveats — a preload fetches the whole variant and a cache MISS has no `Accept-Ranges` to stop at; `crossorigin` must match the element; `preload_links_header` also emits a `Link` header, so preload the track that is about to play rather than a list
- [ ] 3.3 README Status paragraph: name the helper

## 4. Gates

- [ ] 4.1 `bin/test` green
- [ ] 4.2 `bin/rubocop` green
- [ ] 4.3 `openspec validate add-preload-hint-helper` passes
- [ ] 4.4 Outside code review per CLAUDE.md; name the `preconnect` helper and auto-emission from `audioproxy_audio_tag` as out of scope so their absence is not reported as a gap
