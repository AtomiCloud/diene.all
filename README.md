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

## Auth-engine package

`@atomicloud/diene.auth-engine` is the edge-safe authentication and onboarding
engine for Diene applications. It ships dual **ESM + CommonJS** bundles and a
separate TestHelper subpath for consumer tests.

See the [authentication standard](docs/standards/auth/index.md) for resource
registration, token lifetimes, deferred handoff, and per-backend onboarding.

[![npm version](https://img.shields.io/npm/v/@atomicloud/diene.auth-engine)](https://www.npmjs.com/package/@atomicloud/diene.auth-engine)
[![npm downloads](https://img.shields.io/npm/dm/@atomicloud/diene.auth-engine)](https://www.npmjs.com/package/@atomicloud/diene.auth-engine)
[![CI](https://github.com/AtomiCloud/diene.bun-auth-engine/actions/workflows/ci.yaml/badge.svg)](https://github.com/AtomiCloud/diene.bun-auth-engine/actions/workflows/ci.yaml)

### Installation

```bash
bun add @atomicloud/diene.auth-engine
# or
npm install @atomicloud/diene.auth-engine
```

`@logto/js`, `jose`, `zod`, and the Diene result/problem packages are runtime
dependencies and are installed automatically.

### Usage

```ts
// ESM
import { createResourceTree, ServerAuthStateRetriever } from '@atomicloud/diene.auth-engine';
import type { ResourceTree } from '@atomicloud/diene.auth-engine';
import { FakeAuthProvider } from '@atomicloud/diene.auth-engine/test-helper';
```

```js
// CommonJS
const { createResourceTree } = require('@atomicloud/diene.auth-engine');
```
