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

<!-- ### bun-otel -->
<!-- #### source: lib/bun/otel -->

## Library package

`@atomicloud/diene.otel` is the Bun family's OpenTelemetry package, shipped as dual
**ESM + CommonJS** with bundled type declarations, validated on every push and
published on `v*.*.*` tags. It owns the engine-owned config block schema, the
canonical resource identity, the signal lifecycle (init / flush), the pino logs
bridge, and the language-local trace seam — plus framework-free telemetry test
doubles. See the [otel standard](docs/standards/otel/index.md) for the canonical
block, resource mapping, `OTEL_*` precedence, the logs stance, and the trace-seam
ownership boundary.

See the [npm release runbook](https://github.com/AtomiCloud/diene.bun-otel/blob/main/docs/developer/npm-release.md)
for tag publishing, API-key rotation, retry behavior, and the deliberate
no-provenance policy.

[![npm version](https://img.shields.io/npm/v/@atomicloud/diene.otel)](https://www.npmjs.com/package/@atomicloud/diene.otel)
[![npm downloads](https://img.shields.io/npm/dm/@atomicloud/diene.otel)](https://www.npmjs.com/package/@atomicloud/diene.otel)
[![CI](https://github.com/AtomiCloud/diene.bun-otel/actions/workflows/ci.yaml/badge.svg)](https://github.com/AtomiCloud/diene.bun-otel/actions/workflows/ci.yaml)
[![coverage](https://codecov.io/gh/AtomiCloud/diene.bun-otel/branch/main/graph/badge.svg)](https://codecov.io/gh/AtomiCloud/diene.bun-otel)
[![commit activity](https://img.shields.io/github/commit-activity/m/AtomiCloud/diene.bun-otel)](https://github.com/AtomiCloud/diene.bun-otel/commits/main)

### Installation

```bash
bun add @atomicloud/diene.otel
# or
npm install @atomicloud/diene.otel
```

`@atomicloud/diene.interfaces`, `@atomicloud/diene.result`, and
`@atomicloud/diene.core-utils` are runtime dependencies and are installed
automatically.

### Usage

Import the config **schema** from the package root, and the framework-free telemetry
**doubles** from the `@atomicloud/diene.otel/test-helper` subpath:

```ts
// ESM — the engine-owned config block schema, inferred types, and bootstrap:
import { initOtel, otelBlockSchema, type OtelBlock } from '@atomicloud/diene.otel';

const block: OtelBlock = otelBlockSchema.parse(rawConfig.otel);
const telemetry = initOtel(block, appIdentity);

// The consumer lifecycle owns graceful shutdown; the library installs no hooks.
await telemetry.shutdown();

// In-memory trace double and OTel asserters live on the test-helper subpath:
//   import { InMemoryTraceEmitter } from '@atomicloud/diene.otel/test-helper';
```

```js
// CommonJS
const otel = require('@atomicloud/diene.otel');
```

Logging and metrics doubles come from `@atomicloud/diene.interfaces/test-helper`; the
trace double is owned here (RB-19).
