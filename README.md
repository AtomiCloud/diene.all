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

<!-- ### bun-lib -->
<!-- #### source: bun-lib -->

## Library package

`@atomicloud/diene.bun-lib` is the publishable Bun library baseline: a small
TypeScript package shipped as dual **ESM + CommonJS** with bundled type
declarations, validated on every push and published on `v*.*.*` tags. Library
children rescope the package name, description, keywords, and badge URLs from
this scaffold.

See the [npm release runbook](https://github.com/AtomiCloud/diene.bun-lib/blob/main/docs/developer/npm-release.md)
for tag publishing, API-key rotation, retry behavior, and the deliberate
no-provenance policy.

[![npm version](https://img.shields.io/npm/v/@atomicloud/diene.bun-lib)](https://www.npmjs.com/package/@atomicloud/diene.bun-lib)
[![npm downloads](https://img.shields.io/npm/dm/@atomicloud/diene.bun-lib)](https://www.npmjs.com/package/@atomicloud/diene.bun-lib)
[![CI](https://github.com/AtomiCloud/diene.bun-lib/actions/workflows/ci.yaml/badge.svg)](https://github.com/AtomiCloud/diene.bun-lib/actions/workflows/ci.yaml)

### Installation

```bash
bun add @atomicloud/diene.bun-lib
# or
npm install @atomicloud/diene.bun-lib
```

`ioredis` is a runtime dependency and is installed automatically.

### Usage

```ts
// ESM
import { buildSampleKey, createRedisStore, persistSample } from '@atomicloud/diene.bun-lib';
import type { IKeyValueStore, RedisConnection } from '@atomicloud/diene.bun-lib';
```

```js
// CommonJS
const { buildSampleKey, createRedisStore, persistSample } = require('@atomicloud/diene.bun-lib');
```
