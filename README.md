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

## Problems library

`@atomicloud/diene.problems` provides RFC 9457 envelopes, portal-bound typed
registries, error transformers, generic Problems, JSON Schema publication,
row-oriented `Problem` CR content, and a framework-independent TestHelper.
It ships as dual **ESM + CommonJS** with bundled type declarations.

Read the [Problems standard](docs/standards/problems/index.md) before declaring
a service catalog or publishing a primordial-chart row.

[![npm version](https://img.shields.io/npm/v/@atomicloud/diene.problems)](https://www.npmjs.com/package/@atomicloud/diene.problems)
[![npm downloads](https://img.shields.io/npm/dm/@atomicloud/diene.problems)](https://www.npmjs.com/package/@atomicloud/diene.problems)
[![CI](https://github.com/AtomiCloud/diene.bun-problems/actions/workflows/ci.yaml/badge.svg)](https://github.com/AtomiCloud/diene.bun-problems/actions/workflows/ci.yaml)

### Installation

```bash
bun add @atomicloud/diene.problems
# or
npm install @atomicloud/diene.problems
```

### Usage

```ts
import { createGenericProblemRegistry, createProblem } from '@atomicloud/diene.problems';

const registry = createGenericProblemRegistry(errorPortal);
const problem = createProblem(registry.require('entity_not_found'), {
  data: { entityType: 'Note', id: '42' },
});
```

The shipped [usage skill](skills/diene-problems-usage/SKILL.md) covers catalog
declarations and the `/test-helper` matcher/builders. See the
[npm release runbook](docs/developer/npm-release.md) for publication.
