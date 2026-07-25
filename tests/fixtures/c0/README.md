# C0 wire-format fixtures

<!-- ### go-lib-c0-fixtures -->
<!-- #### source: lib/go/api-engine -->

`wire.json` holds the shapes the C0 conformance test
(`tests/unit/wire/c0_conformance_test.go`) consumes: the test loads it at
runtime and validates
`github.com/AtomiCloud/diene.go-api-engine/lib/wire` against it, instead of
hard-coding illustrative values in Go.

## Provenance (honest)

- **Authority:** the C0 contracts standard §1 _Serialization_ — wire formats are
  ISO 8601 / RFC 3339: date `YYYY-MM-DD`, time `HH:mm:ss`, datetime = RFC 3339
  UTC instant, duration = ISO 8601, timezone = **IANA id** (never offsets, never
  abbreviations).
- **Canonical location:** `docs/standards/contracts/` on the `shared` branch.
  The workspace mirror read at materialization time is `goals/c0-contracts.md`
  §1.
- **Materialized:** 2026-07-25 at the `lib/go/api-engine` node, **by hand**,
  from the C0 §1 text above, following the fixture pattern the accepted
  `lib/go/errors-problems` sibling established for its §2/§14 shapes.
- **These are NOT a machine-generated, authoritative C0 artifact.** No such
  generated artifact exists yet. They are the binding artifact for this node
  until C0 publishes machine-generated JSON-Schema fixtures.

## Deterministic later replacement

C0's deliverables commit to a generated per-language export shape. When C0
publishes machine-generated fixtures, **regenerate this file from C0** and the
conformance test re-greens automatically — the test reads the fixture, so only
the fixture content changes, never the test code.

## Coverage

- `datetime` — canonical round trips, non-UTC inputs that must normalize to a
  UTC rendering, and literals that must be rejected.
- `duration` — canonical round trips with their exact nanosecond values, plus
  the rejected set including the calendar designators `Y` and `M`, which have no
  fixed length and so cannot become an exact duration.
- `timezone` — accepted IANA identifiers and the rejected offsets and
  abbreviations.
