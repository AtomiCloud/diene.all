# diene_interfaces

[![pub package](https://img.shields.io/pub/v/diene_interfaces.svg)](https://pub.dev/packages/diene_interfaces)
[![CI](https://github.com/AtomiCloud/diene.dart_interfaces/actions/workflows/ci.yaml/badge.svg)](https://github.com/AtomiCloud/diene.dart_interfaces/actions/workflows/ci.yaml)
[![unit coverage](https://codecov.io/gh/AtomiCloud/diene.dart_interfaces/graph/badge.svg?flag=unit)](https://codecov.io/gh/AtomiCloud/diene.dart_interfaces)
[![meta coverage](https://codecov.io/gh/AtomiCloud/diene.dart_interfaces/graph/badge.svg?flag=meta)](https://codecov.io/gh/AtomiCloud/diene.dart_interfaces)

The Diene family's shared, **implementation-free** boundaries between portable
Dart code and the host: process/clock (`System`), filesystem (`Vfs`), process
execution and stdio (`Terminal`), and the two telemetry emit seams
(`LoggerSink`, `MetricsCollector`).

Every fallible member returns `Result` from
[`diene_result`](https://pub.dev/packages/diene_result) and **never throws** to
communicate an expected failure. The error channel is the canonical RFC 9457
`Problem` from [`diene_problems`](https://pub.dev/packages/diene_problems),
whose `type` URI is minted by the single C0 §2 builder.

```dart
import 'package:diene_interfaces/diene_interfaces.dart';
import 'package:diene_result/diene_result.dart';

// Depend on the narrow seam you need, not on dart:io.
Future<Result<String>> loadConfig(Vfs vfs, String path) => vfs.readText(path);
```

```dart
// In tests, use the shipped in-memory fakes — no mocking framework needed.
import 'package:diene_interfaces/test_helper.dart';

final InMemoryVfs vfs = InMemoryVfs(
  files: <String, List<int>>{'/etc/app.yaml': 'landscape: lapras'.codeUnits},
);
final String text = (await vfs.readText('/etc/app.yaml')).unwrap();
```

## Public surface

| Seam               | Members                                                                                                   |
| ------------------ | --------------------------------------------------------------------------------------------------------- |
| `System`           | `environment`, `currentDirectory`, `nowUtc`, `delay`                                                      |
| `Vfs`              | `exists`, `stat`, `readBytes`, `readText`, `writeBytes`, `writeText`, `list`, `createDirectory`, `delete` |
| `Terminal`         | `interactive`, `run`, `write`, `readLine`                                                                 |
| `LoggerSink`       | `emit`, `flush`                                                                                           |
| `MetricsCollector` | `emit`, `flush`                                                                                           |

Supporting types: `VfsEntry` / `VfsEntryType` / `VfsStat`, `TerminalCommand` /
`TerminalOutput` / `TerminalWrite` / `TerminalRead` / `TerminalChannel`,
`LogRecord` / `LogLevel`, `MetricRecord` / `MetricKind`, and
`TelemetryAttributes`.

Failure vocabulary: `PortName`, `PortErrorCode`, `portProblem`, `portFailure`,
`invalidInput`.

Validators an implementation may reuse: `checkVfsPath`,
`checkTerminalCommand`, `checkTerminalOutput`, `checkTerminalWrite`,
`checkTerminalRead`, `checkLogRecord`, `checkMetricRecord`,
`checkTelemetryAttributes`.

## What this package deliberately does NOT own

- **No trace seam.** Trace test interfaces stay language-local (RB-19).
- **No OTel implementer or exporter.** Dart/Flutter telemetry rides Faro at
  runtime through the frontend machinery.
- **No concrete `dart:io` or Flutter implementation.** This is the seam package;
  real adapters live in the consuming application layer.

## TestHelper

`package:diene_interfaces/test_helper.dart` ships stateful in-memory fakes for
all five seams (`InMemorySystem`, `InMemoryVfs`, `InMemoryTerminal`,
`InMemoryLoggerSink`, `InMemoryMetricsCollector`) plus `expectPortProblem` and
`SeamAssertionFailure`. It depends on **no** test framework, matcher library,
mocking package, Flutter, or exporter, so it adds nothing to a consumer's
production dependency graph. Every fallible member accepts FIFO scripted
results, so failure paths are exercised without exceptions.

Read the [package doc](doc/interfaces.md) for the seam contracts, the S33
extraction boundary, and the documented parity deltas against the
`@atomicloud/diene.interfaces` Bun sibling.

## Development

- `pls setup` resolves the workspace dependencies.
- `pls test` runs the unit, C0 conformance, and TestHelper meta suites.
- `pls test:coverage` enforces the separate unit and meta ledgers.
- `pls deadcode` runs the repository and production-only dead-code passes.
- `pls package:validate` runs the release guard, publish dry-run, and pana.
