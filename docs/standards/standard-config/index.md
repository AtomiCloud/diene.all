# Standard config presets

`@atomicloud/diene.standard-config` ships the AtomiCloud family's **infra config
preset schemas** — `postgres`, `cache`, `kv`, and `storage` — plus a
Testcontainers TestHelper. It ships **schemas only**: it never loads, merges, or
validates. `@atomicloud/diene.config` is the sole merger/validator; a service
composes these presets (with engine-owned blocks and its own keys) into a config
registry, and config validates the composed root once, fail-fast at startup.

`otel`, `auth`, and `http` are **not** here — each engine library
(`lib/bun/otel`, `auth-engine`, `api-engine`) owns and exports its own config
block schema next to the code that reads it (C0 §3). Services compose engine
blocks alongside these infra presets.

The preset shapes are on the **C0 freeze list**: the `postgres`/`cache`/`kv`/
`storage` block keys match key-for-key across the bun, dotnet, and go
standard-config libraries (c0-contracts.md §3). Do not drift the keys.

## Available presets

Every preset is a **keyed map of named connections** — a `Record<KEY, entry>`
whose keys are **UPPERCASE** (R14: connection-pool names). Adding a second
instance (`MAIN` → `REPLICA`) is pure YAML, never a schema change.

| Preset     | Provider (per landscape)      | Semantics                                           | Fields                                                                               |
| ---------- | ----------------------------- | --------------------------------------------------- | ------------------------------------------------------------------------------------ |
| `postgres` | Neon / CNPG / local           | relational                                          | `host`, `port`, `database`, `username`, `password`\*, `ssl`, `pool.{min,max}`        |
| `cache`    | Dragonfly                     | RAM-backed, **ephemeral**; Redis protocol           | `host`, `port`, `password`\*, `db`, `tls`                                            |
| `kv`       | Upstash / lapras              | **persistent**, snapshot durability; Redis protocol | `host`, `port`, `password`\*, `db`, `tls`                                            |
| `storage`  | Tigris (prod) / MinIO (local) | S3-compatible object storage                        | `endpoint`, `region`, `bucket`, `accessKeyId`_, `secretAccessKey`_, `forcePathStyle` |

\* **Secret — blank-in-yaml (R14/M33):** the base YAML carries `""`; the real
value is injected per landscape through the env-override tier. A blank env value
leaves the field unset.

`cache` and `kv` share the Redis connection shape but are **separate blocks** —
their durability contracts differ, so a cache must never be relabeled as a kv.

## Keyed multi-instance

```yaml
postgres:
  MAIN: { host: db, port: 5432, database: app, username: app, password: '', ssl: true, pool: { min: 0, max: 10 } }
  REPLICA: { host: replica, port: 5432, database: app, username: ro, password: '', ssl: true, pool: { min: 0, max: 5 } }
```

Read a named connection fail-fast: `named(config('postgres'), 'MAIN')`.

## Example YAML per preset

Each preset ships an example whose **first line is a generated `$schema`
pointer** (R14 / C0 §3), under
[`examples/`](examples/):

- [`postgres.config.yaml`](examples/postgres.config.yaml)
- [`cache.config.yaml`](examples/cache.config.yaml)
- [`kv.config.yaml`](examples/kv.config.yaml)
- [`storage.config.yaml`](examples/storage.config.yaml)

Each example validates against the JSON schema `generateJsonSchema` emits for a
registry containing that preset — the same schema the loader enforces.

## Composing presets

```ts
import { ConfigRegistry, YamlConfigSource, loadConfig } from '@atomicloud/diene.config';
import { registerStandardConfigs, named } from '@atomicloud/diene.standard-config';

const registry = registerStandardConfigs(ConfigRegistry.create(), {
  which: ['postgres', 'cache', 'kv'] as const,
});
// ...register engine blocks (otel/auth/http) + your own keys here.

const config = await loadConfig(new YamlConfigSource({ dir: './config' }), registry, {
  prefix: 'ATOMI_',
});
const main = named(config('postgres'), 'MAIN');
```

## Block storage

`storage` also ships a deliberately tiny block-storage interface and its one
S3-compatible implementation:

```ts
import { S3BlockStorage, named } from '@atomicloud/diene.standard-config';

const store = new S3BlockStorage(named(config('storage'), 'MAIN'));
const result = await store.save({ key: 'pics/a.png', body: bytes, contentType: 'image/png' });
if (await result.isOk()) console.log((await result.unwrap()).link);
const url = store.getSignedUrl('pics/a.png', { expiresIn: 300 });
```

`save` is railway-oriented (`Result<StoredObject, StorageError>`); `getLink` and
`getSignedUrl` are synchronous. `S3BlockStorage` is **Bun-only** (it uses
`Bun.S3Client` — no extra runtime dependency). Under Node, use the in-memory
fake from the TestHelper.

## TestHelper (`/test-helper`)

The `@atomicloud/diene.standard-config/test-helper` subpath export lets a
consumer int-test its repositories/adapters against real dependencies. Each
start helper boots a container **and** emits a keyed config block valid against
the matching preset schema:

```ts
import {
  startPostgres,
  startCache,
  startKv,
  startStorage,
  InMemoryBlockStorage,
  createS3Bucket,
} from '@atomicloud/diene.standard-config/test-helper';

const pg = await startPostgres({ key: 'MAIN' }); // pg.block is a valid postgres block
// ...run your repository against pg.container...
await pg.stop();

const fake = new InMemoryBlockStorage(); // no container, for unit tiers
```

- `testcontainers` is an **optional peer dependency** — install it in the
  consumer to use the container helpers.
- `InMemoryBlockStorage` is a dependency-free `BlockStorage` fake with
  deterministic links, contract-parity-tested against `S3BlockStorage`.
- `createS3Bucket` creates an extra bucket against a started S3 endpoint.

Consumers never int-test the block-storage interface itself — the interface and
its one S3-compatible implementation are proven here.
