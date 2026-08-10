# C0 Problem fixture provenance

`problem-v1.json` is a byte-for-byte projection of
`contracts/c0/cases/problem.json` from neutral release `c0-fixtures-r1` at
commit `6e657484f25e6e73702617793e0355bf816936aa`. Its file SHA-256 is
`a8c02554c198627df9badc6c2377218556ec8bd3a0b1edcdb20aedeebe43f988`; the
release digest is
`eda331ecba1e899718fa8e8e9b3485d4b746aa66b9c7c1947052ea3e74e2ba45`.

The release uses kebab-case sample IDs. R-E14 and the normative C0 catalog prose
require snake_case wire IDs, so tests consume the neutral fixture verbatim for
envelope members, extensions, segment expansion, and catalog shape while a
dedicated variance test pins `EntityNotFound` to `entity_not_found`.
