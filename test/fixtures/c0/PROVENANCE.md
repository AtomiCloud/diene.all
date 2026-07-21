# C0 conformance fixtures — provenance & replacement gate

These fixtures are **mechanically traced** to the authoritative C0 contract, not
hand-invented inline values.

## Source

- `problem_envelope.json` — the RFC 9457 problem envelope + `data` extension +
  the diene `recoverable` flag, per **`goals/c0-contracts.md` §2** ("Envelope =
  RFC 9457 (`type`, `title`, `status`, `detail`, `instance`) + `data`
  extension"). Its `type` follows the C0 §2 versioned template
  `{scheme}://{host}/docs/{landscape}/{platform}/{service}/{module}/{version}/{id}`
  and is reproduced by `diene_problems`' single-source `problemTypeUri` builder
  (the ONE owned builder — never hand-formatted).

## Deterministic replacement gate

`test/c0_conformance_test.dart` proves each fixture is mechanically derived:

1. The envelope's `type` is asserted **equal** to
   `problemTypeUri(portal: <documented portal>, version: 'v1', id: 'entity-not-found')`
   — so a hand-edited/drifted `type` fails the gate.
2. The envelope round-trips losslessly through `diene_result`'s `Problem`
   (`fromJson` → `toJson`) under canonical (sorted-key) JSON.
3. A deliberately mutated copy is shown to FAIL the gate (the gate discriminates).

When the family ships a shared authoritative C0 fixture set, these files are
replaced by (or symlinked to) that set with no test change — the gate already
binds behaviour to the owned builder + `diene_result` envelope, not to these
bytes.
