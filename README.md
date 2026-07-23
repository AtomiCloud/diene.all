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

## Result and Option monads

### Package status

[![npm version](https://img.shields.io/npm/v/@atomicloud/diene.result)](https://www.npmjs.com/package/@atomicloud/diene.result)
[![npm downloads](https://img.shields.io/npm/dm/@atomicloud/diene.result)](https://www.npmjs.com/package/@atomicloud/diene.result)
[![CI](https://github.com/AtomiCloud/diene.bun-result/actions/workflows/ci.yaml/badge.svg)](https://github.com/AtomiCloud/diene.bun-result/actions/workflows/ci.yaml)
[![coverage](https://codecov.io/gh/AtomiCloud/diene.bun-result/branch/main/graph/badge.svg)](https://codecov.io/gh/AtomiCloud/diene.bun-result)
[![unit coverage](https://codecov.io/gh/AtomiCloud/diene.bun-result/branch/main/graph/badge.svg?flag=unit)](https://codecov.io/gh/AtomiCloud/diene.bun-result/flags/unit)
[![meta coverage](https://codecov.io/gh/AtomiCloud/diene.bun-result/branch/main/graph/badge.svg?flag=meta)](https://codecov.io/gh/AtomiCloud/diene.bun-result/flags/meta)
[![commit activity](https://img.shields.io/github/commit-activity/m/AtomiCloud/diene.bun-result)](https://github.com/AtomiCloud/diene.bun-result/commits/main)

`@atomicloud/diene.result` provides async-native `Result<T, E>` and `Option<T>`
interfaces, their concrete `KResult`/`KOption` implementations, and zero-dependency
factories. It publishes dual ESM/CommonJS bundles and types, plus a framework-free
`/test-helper` subpath and usage skill.

Package description: Result and Option monads with dual-format ESM/CJS builds and a dependency-light /test-helper for AtomiCloud/diene.bun-result

Package keywords: atomicloud, result, option, monad, typescript, esm, commonjs, bun

```bash
bun add @atomicloud/diene.result
```

```ts
import { Ok, Opt } from '@atomicloud/diene.result';

const doubled = await Ok<number, string>(21)
  .map(value => value * 2)
  .unwrapOr(0);

const present = await Opt.fromNative(process.env.HOME).isSome();
```

```js
const { Ok } = require('@atomicloud/diene.result');

async function double(value) {
  return Ok(value)
    .map(current => current * 2)
    .unwrapOr(0);
}
```

Assert variants in downstream suites through the `/test-helper` subpath
(`expectOk`/`expectErr`/`expectSome`/`expectNone`). Read the
[Result and Option standard](docs/standards/result/index.md) for the full API,
serialization, Railway Oriented Programming, and meta-testing convention. See
the [npm release runbook](docs/developer/npm-release.md) for package validation,
release authentication, token rotation, and promotion knobs.
