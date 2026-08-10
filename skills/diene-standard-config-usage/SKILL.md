---
name: diene-standard-config-usage
description: Use when consuming @atomicloud/diene.standard-config — composing the postgres/cache/kv/storage infra presets into a lib/bun/config registry, keyed multi-instance connections, the block-storage interface, or int-testing with the Testcontainers TestHelper (/test-helper).
---

# Diene standard-config usage

Use this skill when a service needs AtomiCloud infra config blocks. This library
ships **preset schemas only** — it never loads, merges, or validates. The
`@atomicloud/diene.config` lib is the sole merger/validator; you compose these
presets (plus engine-owned blocks like otel/auth/http and your own keys) into a
config registry, and config validates the composed root once.

Import only the package root or `/test-helper` — never copy the implementation
or reach into `src/`/`dist/`.

## The presets (C0-frozen, key-for-key across bun / dotnet / go)

- `postgres` — keyed map of named Postgres connections (`host`, `port`,
  `database`, `username`, `password`, `ssl`, `pool.{min,max}`).
- `cache` — Dragonfly (RAM-backed, **ephemeral**); Redis protocol
  (`host`, `port`, `password`, `db`, `tls`).
- `kv` — Upstash / lapras (**persistent**, snapshot durability); same Redis
  connection fields as `cache` but a **separate block** — durability differs, so
  never relabel a cache as kv.
- `storage` — S3-compatible endpoints (Tigris prod / MinIO local:
  `endpoint`, `region`, `bucket`, `accessKeyId`, `secretAccessKey`,
  `forcePathStyle`) + the tiny block-storage interface (`save`/`getLink`/
  `getSignedUrl`) and its one Bun `S3BlockStorage` implementation.

`otel`, `auth`, and `http` are **not** here — each engine lib owns its own block.

## Rules that bite

- **Connection-pool names are UPPERCASE** (R14): `MAIN`, `REPLICA`, `SESSION`.
  Lowercase keys fail validation.
- **Keyed multi-instance is data, not code**: add a second connection by adding
  a YAML key — no schema change, no code change.
- **Secrets are blank-in-yaml** (R14/M33): `password`/`accessKeyId`/
  `secretAccessKey` are `""` in the base YAML and injected per landscape through
  the env-override tier. A blank env value stays unset.
- **Every config YAML's first line is a generated `$schema` pointer** — see
  `docs/standards/standard-config/examples/*.config.yaml`.

## Compose presets into a registry

```ts
import { ConfigRegistry, loadConfig } from '@atomicloud/diene.config';
import { YamlConfigSource } from '@atomicloud/diene.config';
import { registerStandardConfigs, named } from '@atomicloud/diene.standard-config';

const registry = registerStandardConfigs(ConfigRegistry.create(), {
  which: ['postgres', 'cache', 'kv'] as const,
}); // ...then .register(...) your engine blocks + own keys

const config = await loadConfig(new YamlConfigSource({ dir: './config' }), registry, {
  prefix: 'ATOMI_',
});

const main = named(config('postgres'), 'MAIN'); // fail-fast keyed lookup
```

## Block storage

```ts
import { S3BlockStorage, named } from '@atomicloud/diene.standard-config';

const store = new S3BlockStorage(named(config('storage'), 'MAIN'));
const result = await store.save({ key: 'pics/a.png', body: bytes, contentType: 'image/png' });
// result is a Result<StoredObject, StorageError>; getLink()/getSignedUrl() are sync.
```

`S3BlockStorage` is **Bun-only** (uses `Bun.S3Client`). For unit tiers, use the
in-memory fake from `/test-helper`.

## TestHelper (`/test-helper`)

Int-test your repositories/adapters against real deps. Each start helper boots a
container AND emits a keyed config block valid against the matching preset:

```ts
import { startPostgres, startStorage, InMemoryBlockStorage } from '@atomicloud/diene.standard-config/test-helper';

const pg = await startPostgres({ key: 'MAIN' });
const registry = registerStandardConfigs(ConfigRegistry.create(), { which: ['postgres'] as const });
// stub a config from pg.block, run your repository against pg.container, then pg.stop()
```

`testcontainers` is an **optional peer dependency** — install it in the consumer
to use the container helpers. `InMemoryBlockStorage` needs no container.

See `patterns.md` for copyable do/don't recipes and the authoritative
[standard-config standard](https://github.com/AtomiCloud/diene.bun-standard-config/blob/main/docs/standards/standard-config/index.md).
