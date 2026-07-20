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

<!-- ### bun-lib -->
<!-- #### source: bun-lib -->

## Publishable Bun library

[![npm version](https://img.shields.io/npm/v/@atomicloud/bun-lib)](https://www.npmjs.com/package/@atomicloud/bun-lib)
[![npm downloads](https://img.shields.io/npm/dm/@atomicloud/bun-lib)](https://www.npmjs.com/package/@atomicloud/bun-lib)
[![CI](https://github.com/AtomiCloud/diene.bun-lib/actions/workflows/ci.yaml/badge.svg)](https://github.com/AtomiCloud/diene.bun-lib/actions/workflows/ci.yaml)

`@atomicloud/bun-lib` is the dual ESM/CommonJS package template for the
`@atomicloud/diene.*` library family. It publishes JavaScript and declarations
for both import styles and includes its usage skill in the package tarball.

Package description: Publishable dual-format Bun library template for AtomiCloud/diene.bun-lib

Package keywords: atomicloud, bun, library, esm, commonjs, typescript

```bash
bun add @atomicloud/bun-lib
```

```ts
import { buildSampleKey } from '@atomicloud/bun-lib';

const key = buildSampleKey('Bun Lib', 'sample key');
```

```js
const { buildSampleKey } = require('@atomicloud/bun-lib');

const key = buildSampleKey('Bun Lib', 'sample key');
```

See the [Bun library baseline](docs/developer/bun-lib-baseline.md) for package
validation, release authentication, token rotation, and promotion knobs.
