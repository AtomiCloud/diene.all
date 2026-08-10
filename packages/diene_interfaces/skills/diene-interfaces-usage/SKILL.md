---
name: diene-interfaces-usage
description: Use when consuming package:diene_interfaces — injecting the System/Vfs/Terminal/LoggerSink/MetricsCollector seams, handling their Result failures, or reaching for the dependency-light in-memory fakes in tests.
---

# diene_interfaces usage

Import only the public barrel; never reach into `lib/src`:

```dart
import 'package:diene_interfaces/diene_interfaces.dart';
```

## Injecting the seams

Take the **narrowest** seam the component actually needs. A widget that only
needs the time takes `System`, not a bundle:

```dart
final class SessionClock {
  const SessionClock(this._system);
  final System _system;

  Result<DateTime> startedAt() => _system.nowUtc();
}
```

Never accept `dart:io` directly in portable code. This package ships no concrete
implementation on purpose — the real `dart:io`/Flutter adapters live in the
application layer (`flutter-base`), so a library that depends on the seam stays
web-safe and testable.

## Handling failures

Every fallible member returns `Result` and never throws for an expected failure,
so there is nothing to `try`/`catch`:

```dart
final Result<String> config = await vfs.readText('/etc/app.yaml');
final String rendered = config.match(
  ok: (String text) => text,
  err: (Problem problem) => 'unavailable: ${problem.title}',
);
```

Two rules that surprise people:

- **Absence is success.** `system.environment('UNSET')` is `Ok(null)`, and
  `vfs.exists('/missing')` is `Ok(false)`. Only a host fault is an `Err`.
- **A non-zero child exit is success.** `terminal.run(...)` returns
  `Ok(TerminalOutput(exitCode: 2, …))`; check `output.succeeded` yourself. An
  `Err` means the process could not be launched at all.

Build your own seam failures with `portFailure` / `invalidInput` rather than
hand-writing a `Problem`, so the `type` URI keeps coming from the single C0 §2
builder:

```dart
return invalidInput<String>(
  port: PortName.vfs,
  operation: 'readText',
  field: 'path',
  message: 'Path must be absolute',
);
```

Pass your application's real `ErrorPortal` (from `diene_config`) to
`portProblem`/`portFailure` when you have one; the default is the client-local
portal.

## Validating at the boundary

If you write an adapter, reuse the shipped validators instead of inventing
rules: `checkVfsPath`, `checkTerminalCommand`, `checkTerminalOutput`,
`checkTerminalWrite`, `checkTerminalRead`, `checkLogRecord`,
`checkMetricRecord`, `checkTelemetryAttributes`.

## Telemetry

`LoggerSink` and `MetricsCollector` are **emit seams only**. Do not add a Dart
OTel exporter or a trace seam to this package: Dart/Flutter telemetry rides Faro
at runtime through the frontend machinery, and trace test interfaces stay
language-local.

## TestHelper decision

Reach for `package:diene_interfaces/test_helper.dart` in consumer tests — that is
what it is for. It has no test-framework, mocking, or Flutter dependency:

```dart
import 'package:diene_interfaces/test_helper.dart';

final InMemoryVfs vfs = InMemoryVfs(
  files: <String, List<int>>{'/etc/app.yaml': 'landscape: lapras'.codeUnits},
);
```

To exercise a failure path, enqueue a scripted result instead of a mock:

```dart
vfs.enqueueReadTextResult(
  portFailure<String>(
    port: PortName.vfs,
    code: PortErrorCode.permissionDenied,
    operation: 'readText',
    message: 'Not permitted',
  ),
);
```

Assert seam failures with `expectPortProblem` rather than re-deriving the type
URI, status, and `data` shape in every test.

See `patterns.md` for the fake-scripting model, the meta-tier convention, and
how a downstream adapter re-runs the shared contract suite against a real
implementation.
