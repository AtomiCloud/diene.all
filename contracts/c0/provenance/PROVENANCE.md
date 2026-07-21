# C0 fixture release provenance

Release `c0-fixtures-r1` materializes the machine-readable Config and Problem
cases authorized by RB-327. The normative prose source was the workspace
overlay at `/home/kirin/Workspace/atomi/diene/goals/c0-contracts.md` on
2026-07-21.

## Pinned sources

- `goals/c0-contracts.md` (768 lines):
  `7dd7a06279f3078a5e195d4103d01ce9fd1b30a7d88178ec37c3e6f0465c7101`
- `goals/lib/dart-family.md`:
  `ece72edbb18e2c45f6f16e3a4da2172862f7b044d4218292f90e5219da0b5bd6`

The Dart-family source supplies the Dart-define-last and development-override
bindings used by the Config cases. CI never reads either ambient source.

## Extraction rule

The provenance files are verbatim byte copies of the cited section bodies,
including their headings and original line wrapping, with LF endings:

- `problem-schema.md`: `goals/c0-contracts.md` lines 33-51 (§2).
- `config-precedence.md`: `goals/c0-contracts.md` lines 53-118 (§3).
- `problem-catalog.md`: `goals/c0-contracts.md` lines 669-687 (§14).

The cases port the content-accepted owner vectors from Problems commit
`e701b8d4b6729aa6f1e7d8c990be63572d03955b` and Config commit
`734272fb25dd1705c7f83ca4c75c31b296c55e41`, with their rejected local
provenance prose removed. The Config key-normalization vector directly
materializes §3's case-insensitive kebab, snake, camel, and Pascal rule.

## Updating

Any normative prose or case change requires a new `c0-fixtures-rN` release on
the contract-source branch: refresh the pinned source hashes and verbatim
excerpts, update the cases, regenerate `SHA256SUMS`, increment
`contractVersion`, recompute the complete-release digest, obtain independent
review, merge the release into each owner, regenerate projections, and rerun
the owner reviews. Never mutate downstream copies or generated projections by
hand.
