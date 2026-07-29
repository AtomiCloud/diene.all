# Validator changes needed after the marker strip

The ownership-marker rule ("markers only in multi-owner files") required stripping
block-ownership markers from every file whose blocks all came from a single template.
The marker-system code is exempt from edits, so this file records the validator change
the strip now requires instead of making it.

## Validator — `scripts/validate/many-owner.sh`

The script builds a fixed target list and then fails any target that has no keyed
block:

```sh
printf '%s\n' .gitignore .dockerignore Taskfile.yaml CLAUDE.md >"${tmp}"
find nix -maxdepth 1 -type f -name '*.nix' | sort >>"${tmp}"
find .github/workflows -maxdepth 1 -type f \( -name '*.yaml' -o -name '*.yml' \) | sort >>"${tmp}"
...
[ -z "${markers}" ] && echo "❌ many-owner target '${file}' has no keyed block" >&2 && exit 1
```

Two of the four literal targets, and both glob-based rules, now sweep in single-owner
files. Those files are correctly marker-free under the rule, so the validator's "no
keyed block" failure is a stale expectation, not a defect in the files.

### Files the validator still demands markers from, but must not

Literal targets, now marker-free:

- `.dockerignore` — was `workspace` only (three blocks, one owner)
- `Taskfile.yaml` — was `workspace` only

Caught by the `nix/*.nix` glob:

- `nix/fmt.nix` — was `workspace` only

Caught by the `.github/workflows/*` glob:

- `.github/workflows/cd.yaml` — was `workspace` only
- `.github/workflows/ci.yaml` — was `workspace` only
- `.github/workflows/release.yaml` — was `workspace` only
- `.github/workflows/⚡reusable-docker.yaml` — was `workspace` only
- `.github/workflows/⚡reusable-helm.yaml` — was `workspace` only
- `.github/workflows/⚡reusable-precommit.yaml` — was `workspace` only
- `.github/workflows/⚡reusable-release.yaml` — was `workspace` only
- `.github/workflows/🛡️merge-gatekeeper.yml` — was `workspace` only

`.dockerignore` is second in list order, so the run currently exits there and never
reaches the rest. All eleven are listed because all eleven would fail in turn.

### Files that must keep being checked (genuinely multi-owner)

- `.gitignore` — `main`, `workspace`
- `CLAUDE.md` — `main`, `workspace`
- `nix/env.nix` — `main`, `workspace`
- `nix/packages.nix` — `main`, `workspace`
- `nix/pre-commit.nix` — `main`, `workspace`
- `nix/shells.nix` — `main`, `workspace`

Three multi-owner files outside the validator's target list also keep their markers and
would benefit from being checked: `README.md` (`main`, `workspace`), and
`scripts/ci/setup.sh` and `scripts/local/skills-sync.sh` (both
`lib/dotnet/server-engine`, `workspace`).

### What the validator should expect instead

Stop treating "is a `nix/*.nix` file" or "is a workflow file" as proof that a file is
many-owner. A marker-free file is now a legal state; only a file that _has_ markers
makes a claim the validator can check. Two options, either acceptable:

1. **Skip marker-free files.** Replace the hard failure with a `continue` when
   `markers` is empty, keeping the uniqueness and one-provenance-line-per-block checks
   for files that do carry markers. This keeps the globs and stays correct as templates
   add or drop ownership.
2. **Enumerate the many-owner targets.** Drop the two `find` rules and list exactly the
   six files above. More precise today, but needs an edit whenever a file gains or
   loses a second owner.

Option 1 is recommended: it encodes the rule itself ("markers must be well-formed where
they exist; their absence is not an error") rather than a snapshot of today's ownership.

### Probe impact — `probes/many-owner-schema.ts`

Also exempt, and no change is needed under either option. Its mutation probe appends a
second `### workspace` / `#### source: workspace` block to `.gitignore`, which stays
multi-owner and still trips the duplicate-key check, so the gate keeps its teeth. Its
baseline probe asserts the validator is green, so that row is red until the validator is
updated, and under option 1 it goes green again.

### Measured state

Verified with `nix develop .#ci -c pre-commit run --all-files` after the strip: 18 of
19 hooks pass — including `treefmt`, so the strip left no formatting fallout — and the
only failure is `a-many-owner`, reporting `❌ many-owner target '.dockerignore' has no
keyed block`.

Until the validator is updated, red output from `scripts/validate/many-owner.sh` against
the files listed above is expected.
