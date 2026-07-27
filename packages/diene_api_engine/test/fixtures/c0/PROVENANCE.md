# Local problem-envelope vectors — NOT authoritative C0 fixtures

These files are **local test vectors**, not authoritative C0 fixtures.
Authoritative, source-owned C0 fixture conformance for the Dart family is
**INTEGRATION-HELD pending the C0 owner** (RB-303/RB-315). This node does not
relabel a package-local vector as authoritative.

## What these are

- `problem_envelope.json` — a C0 §2-SHAPED RFC 9457 problem envelope + `data`
  extension + the diene `recoverable` flag, kept only as a LOCAL behavioural
  test of `diene_api_engine`'s problem-envelope handling. Its `type` follows the
  C0 §2 versioned template and is checked for local consistency against
  `diene_problems`' single-source `problemTypeUri` builder.

## What the tests do (and do NOT) prove

- `test/c0_conformance_test.dart` proves this engine round-trips the envelope
  losslessly through `diene_result`/`diene_problems`' `Problem`, consumes it via
  `toResult`, and that the vector's `type` is locally consistent with the owned
  builder (a mutated copy fails).
- These are LOCAL checks. They do NOT establish authoritative C0 fixture
  provenance, which requires the C0 owner's shared, source-owned fixture set.

## At integration (conductor / C0 owner owned)

When the family ships the authoritative shared C0 fixture set, replace/point
these vectors at it; the tests already bind behaviour to the owned
`problemTypeUri` builder and the `diene_result`/`diene_problems` envelope, so no
test change is expected beyond swapping the vector source.
