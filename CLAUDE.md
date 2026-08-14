# audioproxy-rails

## Architecture

This is a Rails integration, and ActiveSupport is a runtime dependency. Use it. The one place that
may not is **`Audioproxy::Signer`**: signature building is the piece a future project might want as
a standalone gem, so it depends on stdlib and `base64` only — no ActiveSupport, no Rails, and no
other file in this gem. Everything it needs arrives through its constructor. That is the extraction
seam, and it is the whole of it; `Config` and `UrlBuilder` are free to be Rails-flavoured.

Everything Rails-facing lives under `Audioproxy::Rails` and hooks in through a railtie, not an
engine (no routes, no `app/`, no migrations). Full Rails stays a development dependency.

`test/audioproxy/signer_isolation_test.rb` pins the seam by loading `audioproxy/signer` alone in a
subprocess with Bundler's environment stripped, and asserting it still reproduces a known-answer
vector. If a change to the signer breaks it, the change is wrong, not the test.

That test greps `$LOADED_FEATURES` rather than checking `defined?(ActiveSupport)`, and the
difference matters: a core_ext file like `active_support/core_ext/object/blank.rb` patches `Object`
without ever defining the `ActiveSupport` constant, so a constant check passes while the dependency
is fully present. Two earlier versions of this test were vacuous for exactly that reason. If you
touch the guard, re-verify it by temporarily adding an ActiveSupport require to `signer.rb` and
confirming the test actually fails.

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

Prefer stdlib over dependencies in the core. The one runtime dependency the core does take is
`base64`, which `Signer` requires directly and the gemspec declares. Since Ruby 3.4 that is a
bundled gem rather than a default one, so the declaration is what keeps it from becoming a
`LoadError` in a process where ActiveSupport is not already pulling it in. Do not drop it in
favour of `pack("m0")`; if you ever do, the gemspec dependency and this paragraph go with it.

## Planning

Work is sliced through [OpenSpec](https://github.com/Fission-AI/OpenSpec); changes live in
`openspec/changes/`. A change's `design.md` is binding: if the implementation wants to diverge from a
numbered decision (D1, D2, ...), stop and raise it rather than quietly deviating. When review or
implementation does justify a change, amend the decision and the affected specs in the same commit
as the code, so the artifacts and the behaviour never disagree.

Implement each change on its own branch and worktree, through `wt` rather than raw `git worktree` —
it owns this workflow, and teardown in particular does more than removing a directory:

```bash
wt switch --create --yes <change-name>   # create the branch and worktree, and move into it
wt remove <change-name>                  # after the change is merged and archived; deletes the
                                         # branch too, if it is merged
```

## Testing

```bash
bin/test      # Minitest; boots the dummy Rails app in test/dummy
bin/rubocop   # rubocop-rails-omakase
```

Both must be green, and `openspec validate <change-name>` must pass, before a change is archived.


## Code review

Before a change is archived it must be reviewed by someone — or something — that did not write it.
Same-model self-review collapses the exercise: a model reviewing its own work mostly re-derives its
own reasoning and reports the agreement as confirmation.

**For outside contributions this is the maintainer's step.** Open a pull request as normal; nothing
here asks a contributor to install or pay for a review tool. When an agent implements a change
end-to-end in this repo, it runs the review itself before archiving.

### What the reviewer has to be

Any tool or person meeting these. No particular CLI is required, and none is assumed to be
installed:

- **A different model from the one that wrote the code**, or a human. This is the whole point; an
  in-session self-review or a subagent on the same model is not a substitute.
- **Able to read the repository**, the specs above all.
- **Unable to write to it.** Sandbox it read-only where the tool allows, and commit before the run
  so `git status --short` afterwards proves it mutated nothing.
- **Made to return its findings as its final message.** Reasoning models otherwise spend the last
  turn thinking and return nothing — a clean exit with an empty answer is a distinct failure, not a
  clean review.

### The brief

Correctness here is defined by `design.md` and `specs/**`, so what you hand the reviewer decides
what you get back. In rough order of what has paid off:

- **Give the reviewer the spec, not just the diff.** A reviewer working from the diff alone can only
  offer taste.
- **Order the review by failure mode, not by category.** Byte-correctness first, then inputs that
  produce a plausible-but-wrong URL instead of an error. That second category is where the real
  defects have been.
- **Point it at your own amendments.** If implementation amended a numbered decision, say so and ask
  it to verify the claim from primary sources rather than take the amendment on trust. This is where
  outside review has been worth the most.
- **Name the deferred slices as out of scope**, or you get their absence reported as a gap.
- **State the hard rules** — the extraction seam, no new runtime dependencies, this layer renders
  rather than validates — so the reviewer does not spend its budget fighting them.
- **Ask for severity labels, `file:line` citations, and a concrete failure case per finding.** A
  finding without a reproducible failure case is worth less than no finding.

### Reconciling

Write your own review *before* reading the reviewer's, then build a table: Issue | Self-review |
Reviewer | Agreement.

**Reconcile rather than adopt the verdict.** Findings have gone both ways. Outside reviewers have
caught a silently-dropped config shape that was going to ship, a byte-stability matrix missing its
most-used key, and a permissive branch that was safe for three settings and unsafe for the fourth.
They have also filed confident findings resting on false premises — one about the standard library,
one asserting exact parity with a Go function the code only approximates. Verify every claim against
the code before acting on it, reproduce the failure case in a real process where you can, and record
the ones you reject along with why.

Expect little overlap, and expect the severity labels to need re-grading. On one change, four
defects came from three different places — the author's own review, the outside reviewer, and an
audit of the outside reviewer's reasoning — with none found twice; the reviewer's single finding was
graded HIGH and reproducing all its branches showed it was real but fail-safe.

**Never act on a finding without approval.** The reviewer is a signal generator, not a judge. The
improved code is the deliverable, not the review log.

**A clean review is not a clean change.** The brief decides what gets looked at, so whatever it does
not name stays unexamined, and a SHIP verdict says nothing about it. After two reviews both returned
SHIP on one change, an offhand question about an interaction neither brief mentioned turned up an
untested case immediately. When the reviews come back clean, the useful next move is to ask what the
brief left out, not to treat the verdict as coverage.
