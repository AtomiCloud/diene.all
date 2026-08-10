# C0 fixture release provenance

Release `c0-fixtures-r2` materializes the machine-readable Config, Identity,
Problem, and Result-wire cases authorized by the C0/Dart migration design. The
normative prose source was the workspace overlay at
`/home/kirin/Workspace/atomi/diene/goals/c0-contracts.md` on 2026-07-21.

## Pinned sources

- `goals/c0-contracts.md` (768 lines):
  `7dd7a06279f3078a5e195d4103d01ce9fd1b30a7d88178ec37c3e6f0465c7101`
- `goals/lib/dart-family.md`:
  `ece72edbb18e2c45f6f16e3a4da2172862f7b044d4218292f90e5219da0b5bd6`
- `goals/lib/result-deep-dive.md`:
  `68e9ec021b3c286fa377bfb8ee02373cfab3146d5c6f43ce9d0085c27fefb164`

The Dart-family source supplies the Dart-define-last and development-override
bindings used by the Config cases. The Result deep-dive supplies the tagged
Result and Option wire tuple spellings used by the Result-wire cases. CI never
reads any ambient source.

## Extraction rule

The provenance files are verbatim byte copies of the cited section bodies,
including their headings and original line wrapping, with LF endings:

- `problem-schema.md`: `goals/c0-contracts.md` lines 33-51 (§2).
- `config-precedence.md`: `goals/c0-contracts.md` lines 53-118 (§3).
- `result-semantics.md`: `goals/c0-contracts.md` lines 180-191 (§5).
- `app-handoff.md`: `goals/c0-contracts.md` lines 198-275 (§7).
- `onboarding-claim.md`: `goals/c0-contracts.md` lines 277-376 (§8).
- `edge-docs.md`: `goals/c0-contracts.md` lines 418-481 (§10).
- `token-lifetimes.md`: `goals/c0-contracts.md` lines 634-645 (§12).
- `home-claim.md`: `goals/c0-contracts.md` lines 647-667 (§13).
- `problem-catalog.md`: `goals/c0-contracts.md` lines 669-687 (§14).

The cases port the content-accepted owner vectors from Problems commit
`e701b8d4b6729aa6f1e7d8c990be63572d03955b` and Config commit
`734272fb25dd1705c7f83ca4c75c31b296c55e41`, with their rejected local
provenance prose removed. The Config key-normalization vector directly
materializes §3's case-insensitive kebab, snake, camel, and Pascal rule.
The Identity and Result-wire cases are authored directly from the pinned prose
and the binding `c0-fixtures-r2` design.

## Updating

Any normative prose or case change requires a new `c0-fixtures-rN` release on
the contract-source branch: refresh the pinned source hashes and verbatim
excerpts, update the cases, regenerate `SHA256SUMS`, increment
`contractVersion`, recompute the complete-release digest, obtain independent
review, merge the release into each owner, regenerate projections, and rerun
the owner reviews. Never mutate downstream copies or generated projections by
hand.
