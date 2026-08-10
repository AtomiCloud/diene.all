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

<!-- ### bun-interfaces -->
<!-- #### source: lib/bun/interfaces -->

## Library package

`@atomicloud/diene.interfaces` is the TypeScript family's shared effect-port
contracts package, shipped as dual **ESM + CommonJS** with bundled type
declarations, validated on every push and published on `v*.*.*` tags. It owns
exactly five ports — **System**, **VirtualFileSystem**, **Terminal**,
**LoggerSink**, and **MetricsCollector** — plus framework-free in-memory doubles,
and carries no vendor SDK dependency. See the
[interfaces standard](docs/standards/interfaces/index.md) for port ownership, the
Result-based failure model, and the adapters-vs-contracts-vs-OTel boundary.

See the [npm release runbook](https://github.com/AtomiCloud/diene.bun-interfaces/blob/main/docs/developer/npm-release.md)
for tag publishing, API-key rotation, retry behavior, and the deliberate
no-provenance policy.

[![npm version](https://img.shields.io/npm/v/@atomicloud/diene.interfaces)](https://www.npmjs.com/package/@atomicloud/diene.interfaces)
[![npm downloads](https://img.shields.io/npm/dm/@atomicloud/diene.interfaces)](https://www.npmjs.com/package/@atomicloud/diene.interfaces)
[![CI](https://github.com/AtomiCloud/diene.bun-interfaces/actions/workflows/ci.yaml/badge.svg)](https://github.com/AtomiCloud/diene.bun-interfaces/actions/workflows/ci.yaml)
[![coverage](https://codecov.io/gh/AtomiCloud/diene.bun-interfaces/branch/main/graph/badge.svg)](https://codecov.io/gh/AtomiCloud/diene.bun-interfaces)
[![unit coverage](https://codecov.io/gh/AtomiCloud/diene.bun-interfaces/branch/main/graph/badge.svg?flag=unit)](https://codecov.io/gh/AtomiCloud/diene.bun-interfaces/flags/unit)
[![meta coverage](https://codecov.io/gh/AtomiCloud/diene.bun-interfaces/branch/main/graph/badge.svg?flag=meta)](https://codecov.io/gh/AtomiCloud/diene.bun-interfaces/flags/meta)
[![commit activity](https://img.shields.io/github/commit-activity/m/AtomiCloud/diene.bun-interfaces)](https://github.com/AtomiCloud/diene.bun-interfaces/commits/main)

### Installation

```bash
bun add @atomicloud/diene.interfaces
# or
npm install @atomicloud/diene.interfaces
```

`@atomicloud/diene.result` is a runtime dependency and is installed automatically;
every fallible port method returns its `Result` directly.

### Usage

Import the port **contracts** from the package root, and the framework-free
in-memory **doubles** from the `@atomicloud/diene.interfaces/test-helper` subpath:

```ts
// ESM — the five port contracts from the package root:
import type { System, VirtualFileSystem, Terminal, LoggerSink, MetricsCollector } from '@atomicloud/diene.interfaces';

// In-memory mocks and assertions live on the test-helper subpath:
//   import { InMemorySystem, assertSystemCalls } from '@atomicloud/diene.interfaces/test-helper';
```

```js
// CommonJS
const interfaces = require('@atomicloud/diene.interfaces');
```

Tracing is not part of this package — trace and span contracts are owned by the
OTel package (RB-19).
