# diene_interfaces contract

`diene_interfaces` is the S33 cross-family common-interfaces library for Dart.
It owns the shared, implementation-free boundaries between portable Dart code
and the host, and nothing else.

## Owned seams

| Seam               | Boundary                                       | Members                                                                                                   |
| ------------------ | ---------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `System`           | the process's OWN ambient state                | `environment`, `currentDirectory`, `nowUtc`, `delay`                                                      |
| `Vfs`              | the filesystem                                 | `exists`, `stat`, `readBytes`, `readText`, `writeBytes`, `writeText`, `list`, `createDirectory`, `delete` |
| `Terminal`         | spawning child processes and interactive stdio | `interactive`, `run`, `write`, `readLine`                                                                 |
| `LoggerSink`       | structured log emission                        | `emit`, `flush`                                                                                           |
| `MetricsCollector` | metric sample emission                         | `emit`, `flush`                                                                                           |

`System` and `Terminal` are split on _whose_ process is involved: `System`
answers about the running process, `Terminal` launches and talks to other ones.
A consumer that only needs a fakeable clock therefore never has to accept a
process runner as well.

## The failure contract

Every fallible member returns `Result<T>` (or `Future<Result<T>>`) and **must
not** throw to communicate an expected failure. The error channel is the
canonical `Problem` envelope from `diene_problems`.

`portProblem` is the single place a seam failure becomes an envelope. It builds
the `type` URI through `problemTypeUri` — the ONE C0 §2 builder — so no seam
ever hand-formats the
`{scheme}://{host}/docs/{landscape}/{platform}/{service}/{module}/{version}/{id}`
template. Each `PortErrorCode` fixes its HTTP status and its C0 `recoverable`
flag (only `timeout` and `unavailable` are recoverable), and `data` always
carries `port`, `code`, and `operation`.

Two rules follow from the boundary, not from convenience:

- An **absent** value is a successful answer, not a failure:
  `System.environment` on an unset variable is `Ok(null)`, and `Vfs.exists` on a
  missing path is `Ok(false)`.
- A **non-zero child exit code** is a successfully captured `TerminalOutput`, not
  a transport failure. Only a launch fault is an `Err`. The caller decides
  whether the status matters.

Paths are opaque strings: normalisation and sandbox policy belong to
implementations. `checkVfsPath` is offered TO implementations that want the
POSIX-ish rule (non-blank, NUL-free, absolute); the contract does not mandate it,
because an archive- or memory-backed filesystem may legitimately accept other
shapes.

## C0 conformance

`test/conformance/c0_problem_test.dart` binds the frozen C0 release
`c0-fixtures-r2`. `tool/gen_c0_projection.dart` projects
`contracts/c0/cases/problem.json` (C0 §2 Problem schema) into
`test/fixtures/c0/problem-envelope.json` with a recorded SHA-256, and the suite
proves:

1. the projected bytes still match the recorded digest;
2. `problemTypeUri` reproduces the frozen worked example exactly;
3. every `PortName` × `PortErrorCode` type URI satisfies the template pattern
   **derived from the fixture** (a future template change re-shapes the
   assertion rather than silently passing);
4. a seam envelope carries only the frozen `rfc9457Members` and `extensions`;
5. a seam envelope round-trips through the canonical codec;
6. `recoverable` splits retryable codes from fatal ones.

The `envelopes` and `catalogEntry` vectors are deliberately not projected: they
bind `diene_problems`' own codec and catalog EXPORT surface, which this package
consumes rather than implements.

Dart is exempt from the C0 OTel config block (frontend-only; telemetry rides
Faro).

## S33 extraction boundary (implementation-wave decision, recorded)

S33 open-after-fold item 6 asked _which concrete filesystem helpers move here,
and whether interface mocks or an OTel `TestHelper` owns each test seam_. Both
halves are decided here for Dart.

**Which concrete helpers move: NONE.** This package ships seams and fakes only —
no `dart:io`, no `package:path`, no Flutter. Reasons:

1. It is the family's lowest layer above `diene_result`/`diene_problems`. A
   `dart:io` import here would make the whole family non-web-safe.
2. Pure helpers (slugify, deep-merge, coercions) are `diene_core_utils`' remit;
   putting path helpers here would split "pure utilities" across two libraries.
3. Real adapters need platform decisions (Flutter's app-support directories,
   sandboxing, permissions) that only the application layer can make.
   `flutter-base` owns them as part of the E4 swap-in.

`checkVfsPath` is the deliberate exception: it is a _validator_, not an
implementation, and exists so downstream adapters do not each invent their own
path rule.

**Per-seam mock ownership: all five mocks live HERE**, in
`package:diene_interfaces/test_helper.dart`. For Dart the OTel half of the
question is moot — there is no Dart OTel library at all (family goal: 8 libs, no
otel member; telemetry rides Faro), so no OTel `TestHelper` exists to own the
`LoggerSink`/`MetricsCollector` fakes.

**Cross-family implication worth flagging.** In the families that DO have an otel
member (ts/cs/go), the LOGGING/METRICS seam mocks still need an owner: either
interfaces owns them (this Dart precedent) or the otel lib's `TestHelper` does.
Dart cannot settle that question — its answer is forced by having no otel member,
not chosen. The decision should be made on the `ts` family and cascaded, and a
split answer (interfaces owns the seam, otel owns the mock) would leave Dart's
seam mocks orphaned in every cross-language parity check.

## TestHelper verdict (family TestHelper/meta tier)

**Ships: YES**, as the dependency-light sub-library
`package:diene_interfaces/test_helper.dart` — not the escape-hatch
`diene_interfaces_test_helper` package, because nothing here needs a test
framework.

Contents: `InMemorySystem`, `InMemoryVfs`, `InMemoryTerminal`,
`InMemoryLoggerSink`, `InMemoryMetricsCollector`, `expectPortProblem`, and
`SeamAssertionFailure`.

Usefulness rationale: these are exactly the ports, IO, and non-determinism
consumers must fake — a clock, a filesystem, a process runner, two telemetry
sinks — and `expectPortProblem` removes the type-URI/status/`data` re-derivation
every seam-failure test would otherwise repeat. Every fallible member takes a
FIFO scripted result, so fault injection needs no mocking framework.

Dependency-light proof: `scripts/validate/dart-package.sh` fails if
`test_helper.dart` imports `package:test`, `package:matcher`,
`package:mockito`, or `package:mocktail`.

Meta tier: `test/meta/` is measured against `lib/test_helper.dart` only, at the
single high threshold, under the `meta` codecov flag.

- `assertions_test.dart` is the **assert-the-asserter** suite: every branch of
  `expectPortProblem` is shown to PASS on a known-good envelope and to FAIL on a
  known-bad one (wrong seam, wrong code, wrong operation, tampered status,
  tampered `recoverable`).
- `contract_parity_test.dart` is the **contract parity** suite: one shared
  behavioural suite per seam, applied to the fake. Because this package ships no
  real implementation by design, the parity subject is the _contract_ — and the
  suite is written as reusable functions (`systemContract`, `vfsContract`, …) so
  a downstream adapter re-runs the identical suite against its real
  implementation.
- The `*_fake_test.dart` files cover fixture/builder invariants: seeding,
  normalisation, snapshot immutability, and FIFO script consumption.

## Parity with the Bun sibling

Reference: `lib/bun/interfaces` (`@atomicloud/diene.interfaces`) at `bb4108d`.
Undocumented deltas are a review defect, so every difference is listed.

### Ported

| Bun export                                                                                                | Dart equivalent                                                                                    |
| --------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| `LogLevel`, `LogRecord`, `LoggerSink`, `checkLogRecord`                                                   | same names; `LogLevel.warning` spelled out instead of `warn`                                       |
| `MetricKind`, `MetricRecord`, `MetricsCollector`, `checkMetricRecord`                                     | same names; the metric-name pattern is byte-identical (`metricNamePattern`)                        |
| `TelemetryAttributes`, `checkTelemetryAttributes`                                                         | same names and rules (non-blank NUL-free keys, finite primitive values, key-sorted frozen output)  |
| `VfsEntry`, `VfsStat`, `VirtualFileSystem`, `checkVfsPath`                                                | `VfsEntry`, `VfsStat`, **`Vfs`**, `checkVfsPath`                                                   |
| `Terminal`, `TerminalWrite`, `TerminalRead`, `TerminalChannel`, `checkTerminalWrite`, `checkTerminalRead` | same names                                                                                         |
| `System.execute`, `ProcessRequest`, `ProcessOutput`, `checkProcessRequest`, `checkProcessOutput`          | `Terminal.run`, `TerminalCommand`, `TerminalOutput`, `checkTerminalCommand`, `checkTerminalOutput` |
| `PortName`, `PortErrorCode`                                                                               | same names, same 13-code vocabulary                                                                |
| `portError()`                                                                                             | `portProblem()` / `portFailure()` / `invalidInput()`                                               |
| test-helper fakes for all five ports                                                                      | `InMemory*` fakes for all five seams                                                               |

### Deliberate deltas

1. **Error channel is `Problem`, not `PortError`.** Dart's accepted
   `diene_result` is `Result<T>` with a fixed `Problem` error channel, while Bun
   uses `Result<T, E>`. A Dart `PortError` exception class would be unreachable
   through the family's own monad, so the _vocabulary_ (`PortName`,
   `PortErrorCode`) is ported and the _carrier_ is the canonical envelope. Each
   code additionally fixes an HTTP status and the C0 `recoverable` flag, which
   Bun's `PortError` does not carry. **Forced by the family Result contract.**
2. **Seam ROLE assignment differs for `System`/`Terminal`.** Bun puts process
   execution on `System.execute` and stdio on `Terminal`; Dart puts process
   execution on `Terminal.run` and the process's own ambient state (env, cwd,
   clock, delay) on `System`. No capability is dropped — Dart's `Terminal` also
   carries Bun's `write`/`readLine`/`interactive`. **Deliberate:** the Dart split
   is by _whose_ process, which lets a consumer take a fakeable clock without
   also taking a process spawner. A cross-language reader must map
   `bun System.execute` → `dart Terminal.run`.
3. **No `Checked<T, E>` type.** Bun needs an intermediate accept/reject record
   because its `Result` is not pattern-matchable. Dart's `Result` is a sealed sum
   type, so the `check*` functions return `Result` directly. **Deliberate:** a
   `Checked` clone would be pure duplication.
4. **Dart-only `System` members** (`environment`, `currentDirectory`, `nowUtc`,
   `delay`). Bun has no ambient-state port. **Deliberate addition:** Flutter
   consumers must fake the clock and build-time environment constantly, and the
   alternative is every consumer hand-rolling a clock seam.
5. **Async shape.** Filesystem, process, and stdio members are
   `Future<Result<T>>`; immediate emissions (`emit`) stay synchronous
   `Result<void>`. Bun's are all synchronous. **Forced:** Dart host IO is
   asynchronous.
6. **Acronym casing.** `Vfs`, not `VFS`/`VirtualFileSystem`. **Forced** by Dart
   type-name conventions.
7. **Immutable collection views.** `TerminalCommand.arguments`/`environment`,
   `LogRecord.attributes`, and `MetricRecord.attributes` are copied and exposed
   as unmodifiable views. Bun freezes objects instead. **Idiom parity.**
8. **`stat()` on the filesystem and `flush()` on both telemetry seams** are
   present in both families. Listed only because an earlier Dart draft omitted
   them; they are ported, not added.
9. **No trace seam** — RB-19, in both families.
10. **No OTel implementer** — Dart has no otel member, while `lib/bun/otel`
    implements these seams for real. **Forced by the family shape:** Dart
    telemetry rides Faro at runtime.

Wire-level `Result` and `Problem` equivalence stays owned by `diene_result` and
`diene_problems`. This package duplicates neither codec.
