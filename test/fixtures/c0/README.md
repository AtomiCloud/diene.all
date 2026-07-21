# C0 problem-schema fixtures (authoritative consumption)

<!-- ### dart-lib-c0-fixtures -->
<!-- #### source: lib/dart/problems -->

These JSON fixtures are the **authoritative source** the C0 conformance test
(`test/c0_conformance_test.dart`) consumes — the test loads them at runtime and
validates `diene_problems` against them, instead of hard-coding illustrative
values.

## Provenance

- **Authority:** the C0 contracts standard —
  - §2 _Problem schema_: RFC 9457 envelope (`type`, `title`, `status`,
    `detail`, `instance`) + the `data` extension; type-URI template
    `{scheme}://{host}/docs/{landscape}/{platform}/{service}/{module}/{version}/{id}`
    with a deliberate `{version}` segment.
  - §14 _Problem catalog schema_: each `problems[]` entry is
    `{ id, type, title, status, recoverable, data, endpoints[] }`.
- **Canonical location:** `docs/standards/contracts/problems.md` and
  `docs/standards/contracts/problem-catalog.md` on the `shared` branch
  (`docs/standards/contracts/` is the C0 home). The workspace mirror read at
  materialization time is `goals/c0-contracts.md` §2 (lines 33–51) and §14
  (lines 669–687).
- **Materialized:** 2026-07-21 at the `lib/dart/problems` node, by hand against
  the current C0 text above (no machine-generated C0 fixture artifact exists
  yet).

## Deterministic later replacement / re-green

C0's deliverables commit to a "JSON-schema export shape: each problem publishes
id/title/version + schema of `data`" generated per language from one output
shape. When C0 publishes machine-generated JSON-Schema fixtures, **regenerate
these three files from C0** and the conformance test re-greens automatically —
the test reads fixture files, so no test-code change is required, only the
fixture content. Until then these hand-materialized fixtures are the binding
cross-language artifact for this node.

## Files

- `envelope.json` — C0 §2 envelope shape + a round-trippable sample.
- `catalog-entry.json` — C0 §14 `problems[]` entry shape + a sample.
- `type-uri.json` — C0 §2 type-URI template, segment values, expected expansion.
