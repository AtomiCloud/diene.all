# Validator changes — patch 1

## Removal by ruling, not by staleness

The user ruling of 2026-07-29 deleted hand-written ownership tags from every file,
single-owner and multi-owner alike, and superseded the earlier multi-owner exception
outright. The empirical basis is that the cyanprint resolver never consumed the tags —
it merges on heading boundaries and takes ownership from its own runtime metadata — so
nothing mechanical depended on them.

That ruling **removes the many-owner enforcement**, it does not repair it. The four
artifacts below are gone from this branch:

- `scripts/validate/many-owner.sh` — the validator
- the `a-many-owner` pre-commit hook in `nix/pre-commit.nix`
- `probes/many-owner-schema.ts` — the probe definition
- the `many-owner-schema` row in `probes/features.json`

**This is authorized content removal, not a silenced check.** The distinction is the
whole point of this record, so state it plainly:

- A silenced check is one edited, disabled, or deleted **so that a red result stops
  being reported**. The prohibition on that — never stamp on red — is unchanged and
  still binding on every other check in this repository.
- An authorized removal is one whose **subject no longer exists by ruling**. There are
  no keyed ownership blocks left anywhere in the tree to check, so the validator has no
  subject. Keeping it would assert a contract the ruling abolished.

The ordering matters and is recorded honestly: this validator **was red** before it was
removed, because the tag deletion left it demanding keyed blocks from files that no
longer have any. It is not removed _because_ it was red. It is removed because the
ruling that removed its subject also named it for removal, and it would have been
removed on a green tree by the same authority. Both facts belong in the record.

A previous version of this file argued the opposite disposition — that the validator
should be repaired to treat a marker-free file as legal, and listed the eleven files it
would then have to stop failing. That analysis is **superseded**: it assumed markers
survived somewhere, and under the ruling they do not.

Machine-stamped provenance remains permitted **only** if cyanprint stamps it from its
own metadata. That is a future cyanprint capability and explicitly not this wave, so no
stamping mechanism was added here.

## Hook trim (user ruling, same wave)

The hook set was trimmed in the same pass. Hooks are what a committer waits on, so
several modes of one validator now share one hook; the enforcement mechanisms themselves
are unchanged and each still has its own probe.

### Merged

| Now                | Was                                                               | How                                                    |
| ------------------ | ----------------------------------------------------------------- | ------------------------------------------------------ |
| `a-action-pins`    | `a-action-pins-trusted`, `a-action-pins-non-trusted`              | both modes of `action-pins.sh`, via `validators`       |
| `a-release-config` | `a-release-config`, `a-release-types`                             | `release-config.sh all`, a mode the script already had |
| `a-workflows`      | `a-workflow-wiring`, `a-release-trigger`, `a-release-concurrency` | three modes of `workflows.sh`, via `validators`        |

The `wiring` mode keeps **both halves** unchanged inside the merged hook, per the ruling:
every `scripts/ci` entry point a workflow references exists and is executable, **and**
every orchestrator job resolves to a repository-local reusable workflow that calls one.
Neither half was weakened, reordered, or made conditional.

### Kept split

`a-infisical` and `a-infisical-staged` stay two hooks by explicit ruling, even though
both run the same binary. The full-tree scan and the staged-changes scan answer different
questions and fail for different reasons.

### Dropped

| Hook               | Also removed                                                                             |
| ------------------ | ---------------------------------------------------------------------------------------- |
| `a-cache-tags`     | `scripts/validate/cache-tags.sh`, `probes/cache-tag-shape.ts`, its feature row           |
| `a-helm-docs`      | `probes/hook-helm-docs.ts`, its feature row (the `helm-docs` binary stays)               |
| `a-workflow-names` | the `workflow-names` mode of `workflows.sh`, `probes/workflow-names.ts`, its feature row |

Each drop removes the probe with the hook. `presence-probe-artifacts` requires a probe
definition for every declared feature, so a feature row without its probe file — or the
reverse — would be a genuine red rather than a leftover. All three were **green** when
removed; none was dropped to avoid a failure.

One consequence worth naming: ci.yaml's name is no longer asserted directly, but
`release-trigger` still requires `.on.workflow_run.workflows == ["CI"]`, so a rename of
ci.yaml is still caught — one hop later, by the release trigger check rather than by a
dedicated name check.

## Cache-tag coverage restored as a mode

The later S31 runner/cache ruling introduced a new OS-sensitive contract after the hook
trim above: runner selection is 26.04-first with exact 24.04 fallbacks, and a
cache-eligible Namespace job must use a `-with-cache` venue, one size label, and a
cache tag that rotates with the selected OS. Must-not-share-cache lanes use the matching
bare venue with no cache metadata; this threat-model split prevents isolation lanes from
silently sharing store state. Live run `30670113046` proved why the distinction matters:
the earlier bare-venue-plus-tag shape schedules but cannot attach a cache volume.

The trim's committer-facing target was **hook count**, not enforcement coverage. The
cache-tag check is therefore restored as the `cache-tag-shape` mode of
`scripts/validate/workflows.sh` inside the existing `a-workflows` hook. Workflow runner
labels and their cache metadata sit beside workflow wiring naturally, and the restored
mode adds no hook: the resulting set remains twelve. The old standalone
`scripts/validate/cache-tags.sh` and `a-cache-tags` hook remain deleted.

`probes/cache-tag-shape.ts` and its feature row return because the restored mechanism
needs its own baseline and destructive arms. One mutation pairs the selected 26.04
cache-capable runner with the 24.04 cache tag; another changes that runner to the bare
venue while retaining its cache tag. Both require the mode to fail. The mode identifies
jobs from their exact S31 runner/cache labels, not a retired substring, so the corrected
cache split cannot make the check silently inspect zero jobs.

## Cache eligibility is decided from behavior, not from labels

Review found that the mode above still inferred cache eligibility from the labels it was
validating. "I carry no cache tag" was therefore read as "I am a deliberate
must-not-share-cache lane", so a Nix job that dropped `-with-cache` **together with** its
cache-size and cache-tag labels passed green — the exact un-cacheable shape that made
live run `30670113046` fail with `nscloud-cache-action requires a cache volume to be
configured`. A gate that accepts the failure it exists to prevent is not enforcement, so
the determination is now positive and independent of the labels under test.

A job is an S31 **Nix-store user** because of what its steps do: it uses a Nix setup
action (`AtomiCloud/actions.setup-nix`, `cachix/install-nix-action`,
`DeterminateSystems/nix-installer-action`), invokes `namespacelabs/nscloud-cache-action`,
or runs a `nix develop` / `nix build` / `nix shell` / `nix run` / `nix flake` /
`nix profile` / `nix store` command (`nix-build`, `nix-shell` and `nix-store` included).
The classification never reads `runs-on:`. From it:

- A Nix-store user selects the exact cache-capable venue with its cache-size label and
  its OS-matched cache tag, exactly as before.
- A Nix-store user on the **bare** Namespace venue is legal only as a declared
  must-not-share-cache lane: it records a non-empty job-level
  `env.S31_CACHE_EXEMPT_REASON` and carries no cache-size or cache-tag label. Without
  that record the gate is red, which is the F2 recurrence closed.
- The exemption is **venue-scoped by ruling**: must-not-share-cache lanes are bare
  Namespace lanes, so a Nix-store user on a GitHub-hosted runner is rejected with or
  without a reason. GitHub-hosted lanes never attach a Namespace cache, so an exemption
  recorded there is rejected too.
- A job that is **not** a Nix-store user may not claim the shared Nix-store cache, and
  has no exemption to record, because there is no shared store for it to be excluded
  from.
- Stale and misplaced markers are rejected: an exemption beside a `-with-cache` venue is
  stale, and either S31 marker declared at step level or workflow level instead of
  job-level `env` is misplaced. A whitespace-only marker is not a record.

The 26.04 primary / 24.04 fallback labels, the cache-tag rotation, the
`S31_RUNNER_FALLBACK_REASON` rules and the corrected `-with-cache` / bare split are
unchanged; nothing above relaxes them.

Two mechanical notes worth recording, because both are silent-failure shapes:

- The per-job row is emitted with `\u001f` unit separators rather than tabs. A tab is IFS
  whitespace, so two adjacent empty marker columns would have collapsed into one and
  shifted the classification column — a baseline where no job records either marker is
  precisely the case that would have misparsed.
- The non-vacuity guards are unchanged in number (GitHub-hosted, Namespace,
  cache-eligible) and now also keep the behavioural classification non-vacuous in both
  directions, without a fourth counter: a cache-capable venue is rejected for any job
  that is not a Nix-store user, so a non-zero cache-eligible count proves the classifier
  answered "Nix" at least once, and a GitHub-hosted runner is rejected for any job that
  is one, so a non-zero GitHub count proves it answered "not Nix" at least once. A
  classifier stuck at either answer turns one of those guards red. A counter for the
  bare/exempt branch is deliberately **not** asserted non-zero: this repository has no
  isolation lane (`absol`, `target-pull`, `fleet-independence` are not workspace jobs),
  so asserting it would fail a conformant tree. That branch is covered by probe arms
  instead, and all four counts are printed on success so a vacuous branch is visible.

`probes/cache-tag-shape.ts` grows from three arms to ten, one per independent assertion,
following the release-workflow precedent. The new arms are: the F2 recurrence (bare venue
with both cache metadata labels deleted), a non-Nix job claiming the shared cache, a
stale exemption beside a cache-capable venue, a Nix job moved to a GitHub-hosted runner
even with an exemption, a default `ubuntu-latest` label, an unrecorded 24.04 fallback,
and combined primary/fallback Namespace labels — the last three being the goal's
remaining named mutation classes, which the gate caught but no arm protected. Each arm
fails loudly if its mutation target has drifted out of the workflow, so an arm cannot
degrade into a no-op that asserts a red the gate never had to produce. `expectedImpact`
stays `[]`: every mutation leaves valid YAML, and no other mechanism in the repository
observes runner labels.

The merged `a-workflows` hook is untouched — same four modes, same twelve hooks, and the
retired `scripts/validate/cache-tags.sh` and `a-cache-tags` hook stay deleted.

## A `run:` line counts when it invokes Nix, not when it mentions it

The behavioural determination above was still a substring match over the whole
unparsed `run:` string. Review reproduced the bypass that follows: delete the Nix setup
action from the Docker reusable, change its command to `echo nix develop`, leave the
`-with-cache` venue and both cache labels untouched, and the gate returned exit 0. The
job installs nothing and invokes nothing, so it is precisely the non-Nix lane that must
not claim the shared store — the F1 failure mode reachable through a slightly different
edit.

The two step fields are now read for what they are:

- `uses:` stays a text match, because an action reference **is** the whole value. A Nix
  setup action remains a positive signal on its own, whatever the `run:` script says.
- `run:` is a shell script, so it is read as one. It counts only when shell syntax puts
  a supported Nix command in **command position**: at the start of the script, or after
  a separator (newline, `;`, `&`, `|`, `(`, `)`), optionally behind `VAR=value`
  assignments, shell keywords (`if`, `then`, `while`, `do`, …) or a plain wrapper
  (`command`, `exec`, `env`, `nohup`, `time`, `sudo`). `nix` itself is a multiplexer, so
  it counts only when the next word is `develop`, `build`, `shell`, `run`, `flake`,
  `profile` or `store`; `nix-build`, `nix-shell` and `nix-store` count on their own.

The reader is a lexer, not a shell: it splits the script into words while tracking
single quotes, double quotes, backslash escapes, backticks, `#` comments and heredoc
bodies, then asks one question of the word list. Quoted text, comment text and heredoc
content never become a command word, which is what makes `echo nix develop`,
`printf 'nix develop'`, `# nix develop` and a `<<'EOF'` body all non-Nix.

The scanner is a jq function block inside `cache-tag-shape`; it adds no runtime, no tool
and no hook. Hook count stays twelve, the four modes are unchanged, and the corrected
`-with-cache` / bare split is untouched.

## Two answers were not enough: the unreadable verdict

The section above claimed that resolving every unreadable construct to "no Nix
invocation" was the fail-closed direction. **That claim was wrong**, and review proved
it from two sides.

First, "no Nix invocation" is only safe on a cache-capable venue. On the **bare** venue
it is the opposite of safe: a real Nix job the reader could not make out —
`'nix' develop`, `sudo -u root nix develop`, `sh -c 'nix develop'`, or an invocation
after text that merely looked like a heredoc opener — was recorded as an ordinary
non-Nix lane and passed green with no cache labels **and** no
`env.S31_CACHE_EXEMPT_REASON`. That is exactly the F2 hole the exemption marker exists
to close, re-opened through the classifier instead of through the labels.

Second, "counts as a command" was too eager in the other direction. A `(` was treated as
a command separator wherever it appeared, so `args=(nix develop)`, `((nix-build))`,
`nix-build() { … }` and a parenthesised `case` pattern all produced a command word that
runs nothing. And a script may take the name away from the binary entirely:
`nix() { echo harmless; }` or `alias nix=echo` followed by `nix develop` calls no Nix at
all.

So the `run:` scanner now answers with three states, and the gate acts on all three:

| Verdict          | Meaning                                   | Venue rule                         |
| ---------------- | ----------------------------------------- | ---------------------------------- |
| `nix-store-user` | a supported Nix command definitely runs   | cache-capable venue, as before     |
| `no-nix`         | the script definitely runs no Nix command | may not claim the cache, as before |
| **`unreadable`** | the reader will not guess at this syntax  | **refused on every venue**         |

`unreadable` is refused on cached, bare and GitHub-hosted venues alike, and neither an
exemption marker nor a bare venue excuses it. Only a Nix setup action — matched as text,
never guessed at — settles the question, and the message says so.

What is read positively, rather than refused:

- **Quoting resolves.** A word is carried as its literal value, so `'nix' develop` and
  `"nix" develop` are the command `nix`. Only an expansion (`$CMD`, backticks) leaves a
  word unresolved.
- **Parentheses are read in context.** `(` opens a subshell only where a command may
  start. Directly after a word it is an array literal or a function definition; doubled
  it is arithmetic; after `in` or `;;` it is a `case` pattern. The exceptions are the
  expansion prefixes `$( … )`, `<( … )` and `>( … )`, which do start a command — so
  process substitution and `out=$(nix build)` are still Nix.
- **Leading redirections and `sh -c`.** `>log nix develop` is Nix, and
  `sh -c '<script>'` is answered by reading `<script>` (bounded to three levels).
- **An argument is inert only if its command is.** A Nix command name handed to `echo`,
  `printf`, `grep`, `test`, `case`, `docker` and the like is text. Handed to a command
  the gate does not know — `timeout 10m nix build`, `./run.sh nix build` — it is
  `unreadable`, because that command may well run it.
- **Redefinition is refused.** If a script defines or aliases `nix`, `nix-build`,
  `nix-shell` or `nix-store`, a later invocation of that name is no longer evidence of
  store use, and the script is `unreadable` rather than Nix.

The honest cost of the boundary is a refusal, not a silent pass: a lane written in a
form the reader cannot resolve must add the setup action or simplify its command. The
cost is bounded in practice — every Nix lane in this repository already uses the setup
action — and the direction is now the same on every venue.

`probes/cache-tag-shape.ts` grows to one baseline plus **ten** mutations. The new arm,
`mutation-textual-nix-mention-cache-claim-caught`, runs two independent sabotages in
sequence against the same file, each with its own required refusal: first the reviewer's
exact reproduction (setup action removed, command replaced with `echo nix develop`,
cached labels retained), then the array literal `args=(nix develop)`. They are sequential
rather than combined on purpose — one script carrying both mentions would let a single
red satisfy both assertions, so a regression in either mechanism could hide behind the
other. Every reasoned arm now asserts the refusal **text**, and the text it asserts is
the definite non-Nix message including its `(no Nix setup action and no nix command in
its steps)` parenthetical: the `unreadable` refusal opens with the same clause, and a
looser match would let "cannot be read" stand in for "definitely not Nix".

## Resulting hook set

Twelve hooks declared, down from twenty — eleven at the pre-commit stage plus the
commit-msg hook. `nix/pre-commit.nix` remains the authoritative statement of the set; it
is not restated here, because it changes whenever a hook is added or removed.
`docs/standards/linting/index.md` explains how to read it.

## Upstream classification

Every region touched by this record's work is `workspace`-owned: the trimmed hooks sit
in the workspace block of `nix/pre-commit.nix`, all four removed feature rows carry
`"template": "diene/workspace"`, and every removed script and probe was born on this
branch. No part of it lands in a chain-root-owned region, so it owes no
`UPSTREAM-CHANGES.md` entry. The touched files still appear in that audit's
classification table as changed files.
