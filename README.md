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
