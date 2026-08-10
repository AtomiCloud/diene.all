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

`@atomicloud/diene.config` is the config-loading engine for the AtomiCloud
TypeScript family: a 4-tier merge (base YAML → landscape overlay → build-time
injection → runtime env), fail-fast zod validation on the final layer, and
`$schema` generation. It ships as dual **ESM + CommonJS** with bundled type
declarations across three entry points — the package root, `/build-time`, and
`/test-helper` — validated on every push and published on `v*.*.*` tags.

Read the [configuration standard](docs/standards/config/index.md) for the full
env-override contract, dimension matrix, and TestHelper details. See the
[npm release runbook](https://github.com/AtomiCloud/diene.bun-config/blob/main/docs/developer/npm-release.md)
for tag publishing, API-key rotation, retry behavior, and the deliberate
no-provenance policy.

[![npm version](https://img.shields.io/npm/v/@atomicloud/diene.config)](https://www.npmjs.com/package/@atomicloud/diene.config)
[![npm downloads](https://img.shields.io/npm/dm/@atomicloud/diene.config)](https://www.npmjs.com/package/@atomicloud/diene.config)
[![CI](https://github.com/AtomiCloud/diene.bun-config/actions/workflows/ci.yaml/badge.svg)](https://github.com/AtomiCloud/diene.bun-config/actions/workflows/ci.yaml)

### Installation

```bash
bun add @atomicloud/diene.config
# or
npm install @atomicloud/diene.config
```

`@atomicloud/diene.result`, `@atomicloud/diene.core-utils`, `zod`, and `yaml` are
runtime dependencies and are installed automatically.

### Usage

```ts
// ESM
import { ConfigLoader, ConfigRegistry, YamlConfigSource } from '@atomicloud/diene.config';
import { buildTimeValueMap } from '@atomicloud/diene.config/build-time';
import { InMemoryConfigSource, stubConfig } from '@atomicloud/diene.config/test-helper';
```

```js
// CommonJS
const { ConfigLoader, ConfigRegistry, YamlConfigSource } = require('@atomicloud/diene.config');
```
