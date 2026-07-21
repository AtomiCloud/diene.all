# diene_interfaces

`diene_interfaces` is the shared Dart boundary for process and host I/O. It
provides implementation-free System, VFS, Terminal, structured logging, and
metrics interfaces. Every fallible operation reports through
`package:diene_result`; expected failures are never communicated by throwing.

```dart
import 'package:diene_interfaces/diene_interfaces.dart';
import 'package:diene_result/diene_result.dart';

Future<Result<String>> loadSettings(Vfs files) =>
    files.readText('/config/settings.yaml');
```

Dependency-light in-memory implementations are available from the opt-in test
helper sub-library:

```dart
import 'package:diene_interfaces/test_helper.dart';

final files = InMemoryVfs(
  files: <String, List<int>>{
    '/config/settings.yaml': 'enabled: true'.codeUnits,
  },
  directories: const <String>['/config'],
);
```

See [the interface contract](doc/interfaces.md) for error semantics, the
telemetry boundary, and deliberate Bun-family differences.

## Development

- `pls setup` resolves dependencies.
- `pls lint` runs formatting, analysis, tests, coverage, dead-code passes, and
  release guards.
- `pls test:unit` runs unit and C0 contract tests.
- `pls test:meta` proves the in-memory TestHelper implementations.
- `pls deadcode` runs the whole-package and production-only analyzer passes.
- `dart pub publish --dry-run` validates the publishable package contents.

Actual publication, mirror creation, runtime Faro adapters, and downstream
stacking are intentionally outside this package branch.
