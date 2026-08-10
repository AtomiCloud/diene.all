# diene_problems

<!-- ### dart-lib-readme -->
<!-- #### source: lib/dart/problems -->

RFC 9457 problem-details machinery for the Dart family: the envelope with the
`data` extension, a single-source type-URI builder, a typed registry, an
error→Problem transformer, `LocalError` wrapping, and per-endpoint catalog
export including the `recoverable` flag.

This is the Dart port of the L-bun `problems` contract (C0 §2/§14). It is
frontend-only machinery: there is no runtime error-info HTTP surface, and
telemetry rides Faro via the frontend path, not an otel exporter.

## Install

```yaml
dependencies:
  diene_problems: ^0.1.0
```

## Usage

```dart
import 'package:diene_problems/diene_problems.dart';

final portal = ErrorPortal(
  scheme: 'https',
  host: 'docs.raichu.cluster.atomi.cloud',
  landscape: 'raichu',
  platform: 'dotnet',
  service: 'user',
  module: 'api',
);

// The ONE place a problem type URI is built.
final type = problemTypeUri(portal: portal, version: 'v1', id: 'entity_not_found');

final registry = ProblemRegistry(portal)..register(GenericProblems.entityNotFound);
final catalog = ProblemCatalog(portal: portal)..addGenerics();
final crdContent = catalog.toCrdContent(); // C0 §14 Problem CR payload
```

Wrap an unexpected client exception:

```dart
final problem = await LocalError(sink).wrap(error, StackTrace.current);
```

## TestHelper

`package:diene_problems/test_helper.dart` ships framework-free helpers
(`expectProblem`, `aProblem`, `aCatalogEntry`) usable from any test runner
without adding a test-framework dependency. See
[doc/diene_problems.md](doc/diene_problems.md) and the shipped usage
skill at [skills/diene-problems-usage/SKILL.md](skills/diene-problems-usage/SKILL.md).

## Commands

- `pls setup` — resolve dependencies and sync vendored skills.
- `pls analyze` — `dart analyze`.
- `pls test` — `dart test`.
- `pls test:coverage` — tests with lcov coverage.
- `pls test:meta` — meta tier over `test_helper.dart`.
- `pls lint` — every pre-commit gate.

<!-- ### workspace -->
<!-- #### source: workspace -->

## Shared standards

- [CI/CD workflows](docs/standards/ci-cd/index.md)
- [conventional commits](docs/standards/conventional-commits/index.md)
- [linting and pre-commit](docs/standards/linting/index.md)
- [Nix flakes and development shells](docs/standards/nix/index.md)
- [release automation](docs/standards/semantic-release/index.md)
- [Taskfile conventions](docs/standards/taskfile/index.md)

<!-- ### shared -->
<!-- #### source: shared -->

- [Authorization](docs/standards/authorization/index.md)
- [Date and time](docs/standards/datetime/index.md)
- [Functional practices](docs/standards/functional-practices/index.md)
- [Testing](docs/standards/testing/index.md)
- [Data validation](docs/standards/validation/index.md)
