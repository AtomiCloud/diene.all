# Diene workspace baseline

<!-- ### nix-root -->
<!-- #### source: main -->

Diene's reproducible development environment is managed by Nix. Run `direnv allow` once, then use `pls` tasks from the loaded shell.

<!-- ### workspace -->
<!-- #### source: workspace -->

This branch is the all-features workspace baseline inherited by every downstream sample: split CI/CD, secrets, release configuration, validators, standards, and vendored agent-skill synchronization.

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

<!-- ### bun-base -->
<!-- #### source: bun-base -->

## Bun foundation

See the [Bun baseline](docs/developer/bun-baseline.md) for the language-specific
toolchain, task surface, test tiers, coverage ledgers, build, and maintenance
boundary. TypeScript variants accompany the shared standards for
[date/time](docs/standards/datetime/languages/typescript.md),
[domain-driven design](docs/standards/domain-driven-design/languages/typescript.md),
[functional practices](docs/standards/functional-practices/languages/typescript.md),
[SOLID](docs/standards/solid-principles/languages/typescript.md),
[stateless OOP/DI](docs/standards/stateless-oop-di/languages/typescript.md),
[testing](docs/standards/testing/languages/typescript.md),
[utilities](docs/standards/utilities/languages/typescript.md), and
[validation](docs/standards/validation/languages/typescript.md).

<!-- ### bun-core-utils -->
<!-- #### source: lib/bun/core-utils -->

## Library package

`@atomicloud/diene.core-utils` is the shared utility layer for the TypeScript
family. It ships Result-based key validation, Temporal wire codecs, bounded
concurrency, stable records, hashing, explicit-root filesystem helpers, and
small collection/string utilities as dual **ESM + CommonJS** with bundled type
declarations.

See the [core-utils standard](docs/standards/core-utils/index.md) for the API
contract and the [npm release runbook](https://github.com/AtomiCloud/diene.bun-core-utils/blob/main/docs/developer/npm-release.md)
for tag publishing, API-key rotation, retry behavior, and the deliberate
no-provenance policy.

[![npm version](https://img.shields.io/npm/v/@atomicloud/diene.core-utils)](https://www.npmjs.com/package/@atomicloud/diene.core-utils)
[![npm downloads](https://img.shields.io/npm/dm/@atomicloud/diene.core-utils)](https://www.npmjs.com/package/@atomicloud/diene.core-utils)
[![CI](https://github.com/AtomiCloud/diene.bun-core-utils/actions/workflows/ci.yaml/badge.svg)](https://github.com/AtomiCloud/diene.bun-core-utils/actions/workflows/ci.yaml)
[![unit coverage](https://codecov.io/gh/AtomiCloud/diene.bun-core-utils/branch/main/graph/badge.svg?flag=unit)](https://codecov.io/gh/AtomiCloud/diene.bun-core-utils/flags/unit)

### Installation

```bash
bun add @atomicloud/diene.core-utils
# or
npm install @atomicloud/diene.core-utils
```

The package uses the published `@atomicloud/diene.result@1.0.2` and
`@atomicloud/diene.interfaces@1.0.0` contracts plus the Temporal polyfill.

### Usage

```ts
// ESM
import { formatWireDate, mapWithConcurrency, namespacedKey, slugify } from '@atomicloud/diene.core-utils';

const key = await namespacedKey('Billing API', 'Daily Report').unwrap();
const slug = slugify('Mañana Report');
```

```js
// CommonJS
const { fuzzyIncludes, unique } = require('@atomicloud/diene.core-utils');
```
