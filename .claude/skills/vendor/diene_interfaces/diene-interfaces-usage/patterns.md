# diene_interfaces patterns

## The FIFO scripting model

Every fake in `test_helper.dart` has two modes and prefers the first:

1. **Real in-memory behaviour** — `InMemoryVfs` genuinely stores bytes,
   materialises parent directories, and lists them back sorted;
   `InMemorySystem` answers from a mutable environment map and a fixed clock;
   `InMemoryTerminal` drains seeded stdin lines.
2. **A scripted result**, enqueued per member (`enqueueReadTextResult`,
   `enqueueClockResult`, `enqueueWriteResult`, …). A scripted result is consumed
   FIFO and **short-circuits** that one call; once the queue drains, real
   behaviour resumes.

Script only the failure you are testing, then let real behaviour carry the rest:

```dart
final InMemoryVfs vfs = InMemoryVfs(
  files: <String, List<int>>{'/a.txt': 'ok'.codeUnits},
)..enqueueReadTextResult(
  portFailure<String>(
    port: PortName.vfs,
    code: PortErrorCode.io,
    operation: 'readText',
    message: 'Disk error',
  ),
);

(await vfs.readText('/a.txt')).isErr; // scripted failure
(await vfs.readText('/a.txt')).isOk;  // real behaviour again
```

`InMemoryTerminal.run` is the one member with no default: an unscripted `run` is
an `unexpected-call` failure, because "a process silently succeeded" is never a
safe default in a test.

Every fake records what it saw — `InMemorySystem.requestedDelays`,
`InMemoryTerminal.commands` / `.writes` / `.reads`,
`InMemoryLoggerSink.records` / `.flushCount`,
`InMemoryMetricsCollector.records` / `.flushCount`, `InMemoryVfs.files` /
`.directories`. Snapshots are unmodifiable, so a test cannot mutate the fake's
state through them.

## Asserting seam failures

```dart
expectPortProblem(
  expectErr(await vfs.readText('/missing')),
  port: PortName.vfs,
  code: PortErrorCode.notFound,
  operation: 'readText',
);
```

`expectPortProblem` checks the seam, the code, the code's HTTP status, the C0
`recoverable` flag, and (optionally) the operation, then returns the `Problem`
for further assertions. It throws `SeamAssertionFailure` — a plain exception, so
it works under `package:test`, `flutter_test`, or plain `dart run`. Use
`expectOk` / `expectErr` from `package:diene_result/test_helper.dart` to unwrap.

## Re-running the contract suite against a real adapter

`test/meta/contract_parity_test.dart` exposes the behavioural contract as
reusable functions — `systemContract`, `vfsContract`, `terminalContract`,
`loggerContract`, `metricsContract` — each taking a label and a builder. This
package applies them to the fakes; a downstream adapter applies the _same_
functions to its real implementation:

```dart
void main() {
  vfsContract('LocalVfs', () => LocalVfs(root: tempDir.path));
}
```

That is how fake-vs-real parity is proven without duplicating the suite. Copy
the functions into the adapter's test tree (they are test-tier code, not part of
the published surface).

## The meta-tier convention

`lib/test_helper.dart` is a **dependency-light** sub-library: it imports the
public barrel, `diene_result`, and `diene_problems` — never `package:test`,
`matcher`, `mockito`, or `mocktail`. That keeps it out of a consumer's
production dependency graph, so it can ship inside the main package instead of
a separate `diene_interfaces_test_helper` package.

The meta tier (`test/meta/`, `pls test:meta`, the `meta` codecov flag) measures
the helper itself, on its own ledger, disjoint from the unit ledger over
`lib/src/**`. It owes three kinds of evidence:

- **assert-the-asserter** — every assertion helper is shown to FAIL on a
  known-bad case and PASS on a known-good one. An assertion that cannot fail is
  worse than no assertion.
- **contract parity** — one shared behavioural suite per interface, applied to
  the fake (and re-applied downstream to the real implementation).
- **fixture/builder invariants** — seeding, normalisation, snapshot
  immutability, and script consumption behave as documented.

The tier is conditional: it activates only when a helper and a meta test exist
**together**. A package with no shared assertions deletes both, and the tier
becomes a successful no-op that uploads no `meta` flag.

## Extending the seams

Adding a member to a seam is a **breaking** change for every implementer. Before
doing it, check that the capability is not already covered:

- ambient process state (env, cwd, clock, delay) → `System`;
- anything path-addressed → `Vfs`;
- spawning a process or talking to the session → `Terminal`;
- an observability emission → `LoggerSink` / `MetricsCollector`.

Do **not** add a trace seam or an exporter here (RB-19; Faro owns Dart runtime
telemetry), and do not add a concrete `dart:io` implementation — that belongs in
the application layer. New failure shapes get a new `PortErrorCode`, with its
HTTP status and `recoverable` flag decided at the same time.
