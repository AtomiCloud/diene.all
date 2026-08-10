# Diene workspace baseline

Diene's reproducible development environment is managed by Nix. Run `direnv allow` once, then use `task` tasks from the loaded shell.

<!-- ### workspace -->
<!-- #### source: workspace -->

This branch is the all-features workspace baseline inherited by every downstream sample: split CI/CD, secrets, release configuration, validators, and standards.

## Commands

Run `task --list` for every available task and its description. The task set is
declared in [`Taskfile.yaml`](Taskfile.yaml), whose `includes:` block maps each
namespace to a file under [`tasks/`](tasks); a task shown as `<namespace>:<task>`
is that key in the included file. See [the Taskfile standard](docs/standards/taskfile/index.md) for the
conventions.

## Standards

The conventions this repository follows live under
[`docs/standards/`](docs/standards). Read the standard for the surface you are
changing before you change it. [`CLAUDE.md`](CLAUDE.md) links the ones an agent
reaches for most often; it is a convenience, not a required index, and nothing
checks that it names every surface.

Domain-specific architecture and behavior belongs under
[`docs/domain/`](docs/domain/README.md), not under `docs/standards/`.

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

<!-- ### bun-result -->
<!-- #### source: lib/bun/result -->

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

Package description: Result and Option monads with dual-format ESM/CJS builds and a zero-dependency /test-helper for AtomiCloud/diene.bun-result

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
