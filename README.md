# diene_result

[![pub package](https://img.shields.io/pub/v/diene_result.svg)](https://pub.dev/packages/diene_result)
[![CI](https://github.com/AtomiCloud/diene.dart_result/actions/workflows/ci.yaml/badge.svg)](https://github.com/AtomiCloud/diene.dart_result/actions/workflows/ci.yaml)
[![unit coverage](https://codecov.io/gh/AtomiCloud/diene.dart_result/graph/badge.svg?flag=unit)](https://codecov.io/gh/AtomiCloud/diene.dart_result)
[![meta coverage](https://codecov.io/gh/AtomiCloud/diene.dart_result/graph/badge.svg?flag=meta)](https://codecov.io/gh/AtomiCloud/diene.dart_result)

Sealed, synchronous `Result<T>` and `Option<T>` values for Dart, with
C0-compatible tagged-array wire codecs and a dependency-light consumer test
helper.

```dart
import 'package:diene_result/diene_result.dart';
import 'package:diene_problems/diene_problems.dart';

final Result<int> result = Result<int>.ok(21)
    .map((value) => value * 2)
    .andThen((value) => Result<int>.ok(value));

final String message = result.match(
  ok: (value) => 'answer: $value',
  err: (Problem problem) => problem.title,
);
```

The error channel is the sole RFC 9457 `Problem` identity owned and exported by
`diene_problems`; `diene_result` depends on that package and does not define or
re-export a competing envelope. `serial()` emits the same JSON arrays as the
Bun sibling:

- `['ok', value]` / `['err', problemJson]`
- `['some', value]` / `['none', null]`

Import `package:diene_result/test_helper.dart` in consumer tests for
`expectOk`, `expectErr`, `expectSome`, and `expectNone`. The sub-library has no
test-framework dependencies and adds no runtime dependency beyond the package's
canonical `diene_problems` edge.

Read the [Result standard](doc/result.md) for the complete API,
wire contract, TestHelper guidance, and deliberate Bun-family deltas.

## Development

- `pls setup` resolves development dependencies.
- `pls test` runs unit, C0 conformance, and TestHelper meta suites.
- `pls test:coverage` enforces the separate unit and meta ledgers.
- `pls deadcode` runs repository and production-only dead-code passes.
- `pls package:validate` runs the release guard, publish dry-run, and pana.
