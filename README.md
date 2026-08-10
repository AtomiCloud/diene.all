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

## Frontend utilities

`@atomicloud/diene.frontend-utils` is the portable, SSR-safe frontend spine for
AtomiCloud applications. It ships dual **ESM + CommonJS** entrypoints with
bundled declarations. Core mechanisms are React-free; thin React bindings are
explicit subpaths.

See the [frontend-utils standard](docs/standards/frontend-utils/index.md) and
[npm release runbook](docs/developer/npm-release.md).

Package description: Portable, SSR-safe frontend mechanisms for AtomiCloud applications.

Package keywords: atomicloud, bun, frontend, react, landscape, discovery, accessibility

[![npm version](https://img.shields.io/npm/v/@atomicloud/diene.frontend-utils)](https://www.npmjs.com/package/@atomicloud/diene.frontend-utils)
[![CI](https://github.com/AtomiCloud/diene.bun-frontend-utils/actions/workflows/ci.yaml/badge.svg)](https://github.com/AtomiCloud/diene.bun-frontend-utils/actions/workflows/ci.yaml)

### Installation

```bash
bun add @atomicloud/diene.frontend-utils
# or
npm install @atomicloud/diene.frontend-utils
```

### Usage

```ts
import { createModuleRegistry, defineModule } from '@atomicloud/diene.frontend-utils/module';
import { landscape } from '@atomicloud/diene.frontend-utils/landscape';

const active = landscape({ source: 'binding', value: runtimeBinding.LANDSCAPE });
const modules = createModuleRegistry();
```
