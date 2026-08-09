# Linting

## Running lints

```bash
task lint            # everything, exactly what CI runs
pre-commit run       # the staged files only (what a commit runs)
```

CI runs `pre-commit run --all-files`, so the hook set in `nix/pre-commit.nix` is
the single source of truth: local commits, `task lint`, and CI all execute the
same gates.

## Adding a lint

1. Add a hook to `nix/pre-commit.nix` (one entry: the tool, its files pattern).
2. If the tool comes from the registry or nixpkgs, add it to `nix/packages.nix`.
3. Run `task lint` to see it fire.

- each attribute name is the hook id you pass to `pre-commit run <hook-id>`;
- `name` is the label the run prints;
- `entry` is what actually executes — either a Nix store path
  (`${packages.<tool>}/bin/<tool> …`, so the pinned tool runs) or a call to the
  `validator` helper in that file, which runs a script under `scripts/validate/`
  with a fixed PATH. `dlint` is never routed through the `validator` PATH: it
  runs as the single `a-dlint` hook over every check declared in `dlint.yaml`,
  so adding a check there needs no edit in `nix/pre-commit.nix`;
- `files` is the regex selecting which paths trigger the hook; a hook with no
  `files` runs on every commit;
- `stages` narrows a hook to a non-default stage; a hook without it runs at the
  default pre-commit stage.

That is the whole procedure. A lint that is too slow for every commit still goes
in pre-commit but CI-only concerns can be wired into the CI workflows instead —
prefer the hook unless the cost is real.

Checks configured through `dlint.yaml` run as one hook (`dlint lint`); add or
disable checks there.
