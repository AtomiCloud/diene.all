# C0 problem-schema fixtures

<!-- ### go-lib-c0-fixtures -->
<!-- #### source: lib/go/errors-problems -->

These JSON fixtures are the shapes the C0 conformance test
(`tests/unit/problem/c0_conformance_test.go`) consumes: the test loads them at
runtime and validates `github.com/AtomiCloud/diene.go-errors-problems/lib/problem`
against them, instead of hard-coding illustrative values in Go.

## Provenance (honest)

- **Authority:** the C0 contracts standard —
  - §2 _Problem schema_: RFC 9457 envelope (`type`, `title`, `status`,
    `detail`, `instance`) + the `data` extension and the `recoverable` flag;
    type-URI template
    `{scheme}://{host}/docs/{landscape}/{platform}/{service}/{module}/{version}/{id}`
    with a deliberate `{version}` segment (D8).
  - §14 _Problem catalog schema_: each `problems[]` entry is
    `{ id, type, title, status, recoverable, data, endpoints[] }`.
- **Canonical location:** `docs/standards/contracts/problems.md` and
  `docs/standards/contracts/problem-catalog.md` on the `shared` branch. The
  workspace mirror read at materialization time is `goals/c0-contracts.md`
  §2 and §14.
- **Materialized:** 2026-07-22 at the `lib/go/errors-problems` node, **by hand**,
  copied from the accepted `lib/dart/problems` sibling fixtures (they are the
  identical cross-language artifact) and re-validated against the C0 text above.
- **These are NOT a machine-generated, authoritative C0 artifact.** No such
  generated artifact exists yet (the RB-319 lesson: do not overclaim). They are
  the binding cross-language artifact for this node until C0 publishes
  machine-generated JSON-Schema fixtures.

## Deterministic later replacement

C0's deliverables commit to a generated "JSON-schema export shape" per language
from one output shape. When C0 publishes machine-generated fixtures,
**regenerate these three files from C0** and the conformance test re-greens
automatically — the test reads fixture files, so only the fixture content
changes, never the test code.

## Files

- `envelope.json` — C0 §2 envelope shape + a round-trippable sample.
- `catalog-entry.json` — C0 §14 `problems[]` entry shape + a sample.
- `type-uri.json` — C0 §2 type-URI template, segment values, expected expansion.
