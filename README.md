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

<!-- ### api-engine -->
<!-- #### source: api-engine -->

## API engine package

`@atomicloud/diene.api-engine` turns generated Kiota TypeScript SDKs into an
immutable multi-backend client tree whose calls always return
`Result<T, Problem>`. It ships ESM, CommonJS, declarations, and a
`@atomicloud/diene.api-engine/test-helper` subpath.

### Installation

```bash
bun add @atomicloud/diene.api-engine
```

### Registration

Register API problems in the application's existing registry, then provide one
complete binding list. There is no later registration point.

```ts
const engine = registerApiProblems(problemRegistry).andThen(problems =>
  createApiEngine({
    problems,
    bindings: [
      {
        coordinate: { landscape: 'prod', platform: 'commerce', service: 'orders', module: 'public' },
        baseUrl: config.ordersApiUrl,
        resource: config.ordersResource,
        auth: ordersAuthStateRetriever,
        createClient: ({ baseUrl, fetch }) => createOrdersKiotaClient({ baseUrl, fetch }),
      },
    ],
  }),
);
```

Each backend owns one config-derived hostname, one published
`IAuthStateRetriever`, and one auth-engine `ResourceKey`. Api-engine derives the
canonical resource key and reads only its entry from `TokenSet.accessTokens`, so
tokens cannot bleed between backends.

Resolve clients and invoke their structurally Kiota-shaped namespaces through
`Result`; use `match`, `map`, or `andThen`, not throwing `unwrap`. Only opaque
no-status failures receive a second attempt. Rescue is an injected trip callback
after both attempts; the application owns all routing.

See [the domain contract](docs/domain/README.md) for the reconciliation matrix,
auth flow, retry rules, and TestHelper guidance.
