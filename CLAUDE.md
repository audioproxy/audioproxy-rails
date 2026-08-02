# audioproxy-rails

## Architecture

The URL builder lives in a Rails-free `Audioproxy` namespace: plain Ruby, stdlib only, no Rails
constants. It must stay extractable to a standalone gem with a `git mv`. Everything Rails-facing
lives under `Audioproxy::Rails` and hooks in through a railtie, not an engine (no routes, no `app/`,
no migrations). Rails is a development dependency only.

`test/audioproxy/rails_free_load_test.rb` pins that seam by loading the core in a subprocess with
Bundler's environment stripped. If a change to the core breaks it, the change is wrong, not the test.

Correctness here is byte-exactness against the audioproxy server's signer. A wrong byte does not
raise; it 403s at the proxy at request time, far from the call site. Two consequences:

- **Fail loudly at config time or call time.** Never emit a plausible-but-wrong URL. A `nil` source,
  a malformed options string, a `default_options` value of the wrong shape, an endpoint carrying
  credentials or a query all raise rather than producing something that looks fine and 403s later.
  When adding a new input, ask what a typo in it produces: if the answer is "a valid-looking URL for
  the wrong variant", it needs validation.
- **The known-answer vectors in `test/fixtures/signature_vectors.rb` are the contract.** They are
  copied from the server's published vectors. Never regenerate them from this gem's own
  implementation, which would make the test assert only that the code agrees with itself.

Prefer stdlib over dependencies in the core. Base64 is handled with `pack("m0")`/`tr`/`delete`
rather than the `base64` gem, so its un-defaulting in newer Rubies is a non-issue.

## Planning

Work is sliced through [OpenSpec](https://github.com/Fission-AI/OpenSpec); changes live in
`openspec/changes/`. A change's `design.md` is binding: if the implementation wants to diverge from a
numbered decision (D1, D2, ...), stop and raise it rather than quietly deviating. When review or
implementation does justify a change, amend the decision and the affected specs in the same commit
as the code, so the artifacts and the behaviour never disagree.

Implement each change on its own branch and worktree:

```bash
git worktree add ../audioproxy-rails.<change-name> -b <change-name>
```

## Testing

```bash
bin/test      # Minitest; boots the dummy Rails app in test/dummy
bin/rubocop   # rubocop-rails-omakase
```

Both must be green, and `openspec validate <change-name>` must pass, before a change is archived.

## Code review

Before archiving a change, get a second opinion from a reviewer that did not write the code —
another person, or a different model than the one that implemented it. Same-model self-review
collapses the value of the exercise.

What has actually paid off here, in rough order of value:

- **Give the reviewer the spec, not just the diff.** Correctness in this repo is defined by
  `design.md` and `specs/**`, so a reviewer working from the diff alone can only offer taste.
- **Order the review by failure mode, not by category.** Byte-correctness first, then inputs that
  produce a plausible-but-wrong URL instead of an error. That second category is where the real
  defects have been.
- **Name the deferred slices as out of scope**, or you get their absence reported as a gap.
- **Reconcile against your own review rather than adopting the verdict.** Findings have gone both
  ways: an outside reviewer caught a silently-dropped config shape that was going to ship, and also
  filed a confident finding resting on a false premise about the standard library. Verify every
  claim against the code before acting on it, and record the ones you reject along with why.
- **Ask for severity labels and file:line citations**, and require the findings as the final
  message: reasoning models otherwise spend the last turn thinking and return nothing.
