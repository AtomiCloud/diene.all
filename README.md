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

`@atomicloud/diene.standard-config` ships the AtomiCloud family's **infra config
preset schemas** — `postgres`, `cache`, `kv`, `storage` — plus a Testcontainers
TestHelper (`/test-helper`). It ships **schemas only**: `@atomicloud/diene.config`
is the sole merger/validator, and a service composes these presets (with
engine-owned blocks and its own keys) into a config registry. Shipped as dual
**ESM + CommonJS** with bundled type declarations.

Read the [standard-config standard](docs/standards/standard-config/index.md) for
the presets, keyed multi-instance convention, example YAMLs, and TestHelper
usage. See the [npm release runbook](https://github.com/AtomiCloud/diene.bun-standard-config/blob/main/docs/developer/npm-release.md)
for tag publishing, API-key rotation, retry behavior, and the deliberate
no-provenance policy.

[![npm version](https://img.shields.io/npm/v/@atomicloud/diene.standard-config)](https://www.npmjs.com/package/@atomicloud/diene.standard-config)
[![npm downloads](https://img.shields.io/npm/dm/@atomicloud/diene.standard-config)](https://www.npmjs.com/package/@atomicloud/diene.standard-config)
[![CI](https://github.com/AtomiCloud/diene.bun-standard-config/actions/workflows/ci.yaml/badge.svg)](https://github.com/AtomiCloud/diene.bun-standard-config/actions/workflows/ci.yaml)

### Installation

```bash
bun add @atomicloud/diene.standard-config
# or
npm install @atomicloud/diene.standard-config
```

`@atomicloud/diene.config` and `zod` are peer dependencies; `testcontainers` is
an optional peer dependency needed only for the `/test-helper` container glue.

### Usage

```ts
// ESM
import { registerStandardConfigs, named, S3BlockStorage } from '@atomicloud/diene.standard-config';
import type { PostgresEntry, StorageEntry } from '@atomicloud/diene.standard-config';
```

```js
// CommonJS
const { registerStandardConfigs, named } = require('@atomicloud/diene.standard-config');
```
