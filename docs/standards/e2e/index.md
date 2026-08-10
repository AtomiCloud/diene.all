# Bun family e2e version train

`@atomicloud/diene.e2e` is the single dependency for a coherent AtomiCloud Bun
library family. It carries ten runtime members: `result`, `interfaces`,
`core-utils`, `config`, `problems`, `otel`, `auth-engine`, `api-engine`,
`standard-config`, and `frontend-utils`.

## Train dependency model

The train declares registry-bound tilde ranges. `result` uses `~1.0.2`; every
other member uses `~1.0.0`. A tilde admits compatible patches without admitting
the next minor. Members still release independently; a train maintainer reviews
and commits each member move manually as `dep(<member>): from vX to vY`. There
is no Renovate-managed train and no automatic member bump. Every named member
scope is configured as a minor train release in `atomi_release.yaml`.

Use the train when an application consumes several family members and needs one
tested compatibility decision. Depend directly on a member when a package
truly needs only that member, must publish a reusable API in terms of its types,
or cannot accept the train's full compatibility cadence.

## Runtime imports

The root offers frozen namespaces plus a small collision-free set of common
identities:

```ts
import { ConfigRegistry, Ok, initOtel, type Problem, type Result } from '@atomicloud/diene.e2e';
import { api, auth, config, otel, result, standardConfig } from '@atomicloud/diene.e2e';
```

Prefer a transparent namespaced subpath for a broader member API:

```ts
import { createApiEngine } from '@atomicloud/diene.e2e/api';
import { registerStandardConfigs } from '@atomicloud/diene.e2e/standard-config';
```

The ten runtime subpaths are `/result`, `/interfaces`, `/core-utils`, `/config`,
`/problems`, `/otel`, `/auth`, `/api`, `/standard-config`, and
`/frontend-utils`. These are identity-preserving passthroughs, not forks.

## Test helpers and harness glue

Import-gated helper code lives under `/test-helper`. It exposes e2e's Garden and
Bruno glue plus frozen helper namespaces. Transparent helper passthroughs exist
for `result`, `interfaces`, `config`, `problems`, `otel`, `auth`, `api`,
`standard-config`, and `frontend-utils`:

```ts
import { createBrunoEnvironment, resolveGardenPreviewEndpoint } from '@atomicloud/diene.e2e/test-helper';
import { InMemoryTraceEmitter } from '@atomicloud/diene.e2e/otel/test-helper';
import { startPostgres } from '@atomicloud/diene.e2e/standard-config/test-helper';
```

There is deliberately no `/core-utils/test-helper`. `testcontainers` is an
optional peer and is loaded only when a standard-config container start helper
is called. Always stop every returned container in `finally`.

Garden resolution takes the final hostname
`module.service.platform.instance.landscape.zone` and a matching namespace
fixture. It validates both and defaults to HTTPS; pass `protocol: 'http'`
explicitly only for a local endpoint. Bruno glue produces a frozen string map
with `baseUrl`, optional `accessToken`, and collection variables.

## Downstream transfer and retired registry bridge

R-E12 downstream transfer applies: ship this standard and the thin
`diene-e2e-usage` skill with the package, then let the workspace skills-sync
mechanism transfer package skills to consumers. Do not copy or aggregate the
ten member usage skills into this package; each installed member owns its own.

R-E22 authorized temporary build/test scaffolding while standard-config was
unavailable from the registry. That bridge earned no release or completion
credit. It was removed once `@atomicloud/diene.standard-config@1.0.0` became
available: the manifest now has no override, `vendor/` is absent, and the lock
resolves the declared `~1.0.0` range from npm. Do not restore a vendored bridge
without a new lead ruling.
