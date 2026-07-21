# Diene Result agent guide

<!-- ### dart-result-agent -->
<!-- #### source: lib/dart/result -->

Use the repository's Nix shell for every command. Read
[the Nix standard](docs/standards/nix/index.md) before changing the flake or
`nix/` modules. Keep many-owner files in keyed, source-attributed blocks and
never hand-edit `.claude/skills/vendor/`.

## Result package

Read [the Result standard](doc/result.md) before changing the
public API, C0 wire representation, or TestHelper. The public entrypoints are
`package:diene_result/diene_result.dart` and
`package:diene_result/test_helper.dart`; `lib/src` is internal.

The package is frontend-compatible but contains no Flutter SDK dependency, no
telemetry implementation, and no SSR surface. Consumer assertions stay
dependency-light and must not import `package:test`, matcher libraries, or a
mocking framework.

## Repository standards

- [CI/CD workflows](docs/standards/ci-cd/index.md)
- [conventional commits](docs/standards/conventional-commits/index.md)
- [linting and pre-commit](docs/standards/linting/index.md)
- [release automation](docs/standards/semantic-release/index.md)
- [Taskfile conventions](docs/standards/taskfile/index.md)
- [testing](docs/standards/testing/index.md)
- [functional practices](docs/standards/functional-practices/index.md)
- [domain-driven design](docs/standards/domain-driven-design/index.md)
- [date and time](docs/standards/datetime/index.md)
- [utility libraries](docs/standards/utilities/index.md)
- [data validation](docs/standards/validation/index.md)

Domain-specific documentation belongs under [docs/domain/](docs/domain/README.md).
