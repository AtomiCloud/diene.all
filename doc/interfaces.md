# Interface contract

## Owned seams

The package owns five small, implementation-free boundaries:

- `System`: environment, current-directory, UTC clock, and delay operations.
- `Vfs`: byte/text file access, directory traversal, creation, and deletion.
- `Terminal`: process invocation with captured exit status and output.
- `LoggerSink`: structured log emission.
- `MetricsCollector`: counter, gauge, and histogram sample emission.

All host failures cross these boundaries as `Result<T>` values from
`diene_result`. Implementations must not catch a failure merely to throw a new
exception, and callers must not need exception handling for expected I/O or
telemetry failures. A non-zero child exit status is captured output, not a
Terminal transport failure.

The package intentionally owns no trace seam. The cross-family ruling keeps
trace test interfaces language-local. Dart also has no OTel package or exporter:
Flutter runtime adapters send logging and metrics through the frontend Faro
path. Those adapters are downstream consumer work, not part of this package.

## TestHelper

`package:diene_interfaces/test_helper.dart` ships stateful, dependency-light
in-memory implementations for all five seams. It has no dependency on `test`, a
matcher library, Flutter, a mocking framework, or an exporter. FIFO scripted
results allow consumers to exercise failure paths without exceptions.

The meta suite owns the fake-contract evidence. Runtime adapter parity will be
completed by applying the same behavioral contract to the later Flutter/Faro
adapters after conductor stacking.

## Bun-family parity and deliberate deltas

The conceptual surface matches the common Bun-family boundary: System, VFS,
Terminal, logger-sink, and metrics-collector seams sit between result and core
utilities, and test helpers own the in-memory implementations.

Deliberate Dart deltas are:

- async I/O is encoded as `Future<Result<T>>` while immediate emissions use
  `Result<void>`;
- the acronym is spelled `Vfs` to follow Dart type-name conventions;
- terminal non-zero exits remain successful captured values;
- there is no trace interface in common interfaces;
- there is no Dart OTel implementation or exporter; Flutter uses Faro;
- immutable collection views protect command attributes and emitted metadata.

Wire-level Result and Problem equivalence remains owned by `diene_result` and
the C0 contracts. This package does not duplicate their codecs or envelopes.
