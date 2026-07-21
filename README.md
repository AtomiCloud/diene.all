# diene_api_engine

<!-- ### nix-root -->
<!-- #### source: main -->

Diene's reproducible development environment is managed by Nix. Run `direnv allow` once, then use `pls` tasks from the loaded shell.

<!-- ### lib-dart-api-engine -->
<!-- #### source: lib/dart/api-engine -->

The typed OA3 backend-client engine for the diene Dart family. It wraps
generated OpenAPI SDK calls into `Result<T, Problem>`, registers N backends on
the LPSM client tree with per-backend auth, retries once on a hard network
failure, and ships a dormant disk-cached rescue router for same-landscape
address failover. Client-side only; the family is frontend-only (no OTel
library — telemetry rides Faro).

## Commands

- `pls setup` — resolve dependencies and sync vendored skills.
- `pls analyze` / `pls test` / `pls test:coverage` / `pls test:meta`.
- `pls deadcode` — two dead-code passes (no exclusion lists).
- `pls manifest-guard` — verify pubspec/VERSION/tag agree (+ negative drill).
- `pls publish:dry-run` — validate package hygiene without publishing.
- `pls lint` — run every pre-commit gate.

## Usage

See [docs/standards/api-client/index.md](docs/standards/api-client/index.md)
for the register-a-backend walkthrough and the Result-typed call convention.
The shipped usage skill lives at
[skills/diene-api-engine-usage/SKILL.md](skills/diene-api-engine-usage/SKILL.md).

## Layout

- `lib/diene_api_engine.dart` — public barrel.
- `lib/test_helper.dart` — dependency-light fakes/assertions/builders
  (`package:diene_api_engine/test_helper.dart`), no test-framework deps.
- `lib/src/**` — engine, transport, bridge, client tree, config block schema,
  and the `rescue/**` router.

## Standards

- [CI/CD workflows](docs/standards/ci-cd/index.md)
- [conventional commits](docs/standards/conventional-commits/index.md)
- [Nix flakes and development shells](docs/standards/nix/index.md)
- [release automation](docs/standards/semantic-release/index.md)
- [testing](docs/standards/testing/index.md)
