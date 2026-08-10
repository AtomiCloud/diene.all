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
