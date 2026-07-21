# diene_e2e

<!-- ### dart-lib -->
<!-- #### source: dart-lib -->

The L-dart family **version-train** and consumer **test-harness**. A consumer
(flutter-base's E4 swap-in) depends on this single package to get a coherent set
of the seven L-dart libraries at once, and imports
`package:diene_e2e/test_helper.dart` for the family's bundled test helpers plus
this package's own harness glue: a stub HTTP server, journey drivers, plain-throw
assertions, and the shared C0 app-handoff (deferred-login) fixture.

- Runtime train + owned contract models: `import 'package:diene_e2e/diene_e2e.dart';`
- Dependency-light test harness: `import 'package:diene_e2e/test_helper.dart';`

Dart is frontend-only, so this package ships no telemetry surface. See
[doc/index.md](doc/index.md) for the train model, harness usage, and the
deliberate deltas versus the `lib/bun/e2e` sibling.

The rest of this file is the inherited workspace baseline.

<!-- ### nix-root -->
<!-- #### source: main -->

Diene's reproducible development environment is managed by Nix. Run `direnv allow` once, then use `pls` tasks from the loaded shell.

<!-- ### workspace -->
<!-- #### source: workspace -->

This branch is the workspace baseline inherited by every downstream sample: split CI/release workflows, secrets, release configuration, validators, standards, and vendored agent-skill synchronization.

## Commands

- `pls setup` — synchronize installed diene package skills.
- `pls lint` — run every pre-commit gate.
- `pls secret:scan` — scan tracked content for secrets.
- `pls skills:sync` — rebuild `.claude/skills/vendor/` from installed packages.

## Standards

- [CI/CD workflows](docs/standards/ci-cd/index.md)
- [conventional commits](docs/standards/conventional-commits/index.md)
- [Infisical and secrets](docs/standards/infisical/index.md)
- [linting and pre-commit](docs/standards/linting/index.md)
- [Nix flakes and development shells](docs/standards/nix/index.md)
- [release automation](docs/standards/semantic-release/index.md)
- [service-tree identity](docs/standards/service-tree/index.md)
- [shell scripts](docs/standards/shell-scripts/index.md)
- [Taskfile conventions](docs/standards/taskfile/index.md)

<!-- ### shared -->
<!-- #### source: shared -->

## Shared standards

- [Authorization](docs/standards/authorization/index.md)
- [Contributor documentation](docs/standards/contributor-docs/index.md)
- [Date and time](docs/standards/datetime/index.md)
- [Domain-driven design](docs/standards/domain-driven-design/index.md)
- [Functional practices](docs/standards/functional-practices/index.md)
- [Software design philosophy](docs/standards/software-design-philosophy/index.md)
- [SOLID principles](docs/standards/solid-principles/index.md)
- [Stateless OOP and dependency injection](docs/standards/stateless-oop-di/index.md)
- [Testing](docs/standards/testing/index.md)
- [Three-layer architecture](docs/standards/three-layer-architecture/index.md)
- [Utility libraries](docs/standards/utilities/index.md)
- [Data validation](docs/standards/validation/index.md)

Domain-specific documentation belongs under [docs/domain/](docs/domain/README.md).
The `docs/standards/contracts/` location is reserved for the separately owned C0
contracts standard.
