---
name: diene-go-standard-config-usage
description: Use the diene Go standard-config presets — the four frozen infra blocks (postgres/cache/kv/storage), composing them into a service root schema, the keyed multi-instance contract, and the Testcontainers TestHelper.
---

# Diene Go standard-config usage

`github.com/AtomiCloud/diene.go-standard-config` publishes the four frozen infra
configuration blocks of C0 §3 — `postgres`, `cache`, `kv`, `storage` — as
draft-2020-12 JSON Schema fragments, plus the Testcontainers glue that boots each
one and hands back the matching config block.

It ships **presets only**. It never loads, merges, or validates a document.
`github.com/AtomiCloud/diene.go-config` is the sole merger and validator.

Every fallible call returns `(T, error)` where the error carries an RFC 9457
`problem.Problem`; recover it with
`var pe *problem.Error; errors.As(err, &pe)`.

Start with the compiling examples in `lib/standardconfig/example_test.go` and
`testhelper/example_test.go`.

## Composing a root schema

There is no one-call bootstrap, and asking for one is the most common mistake.
A service composes its OWN root schema: config's app block, one line per engine
block it uses, one line per infra preset it needs, and its own keys.

```go
schema := config.ComposeSchema(
    config.AppBlockSchema(),
    config.NewBlock(otel.BlockKey, false, otel.JSONSchema()),
    config.NewBlock(authengine.ConfigBlockKey, false, authengine.ConfigBlockSchema()),
    config.NewBlock(standardconfig.PostgresBlockKey, true, standardconfig.PostgresSchema()),
    config.NewBlock(standardconfig.CacheBlockKey, true, standardconfig.CacheSchema()),
    config.NewBlock("billing", true, ownKeysFragment),
)
```

Do: register only the presets the service actually has. A required block with no
YAML behind it fails validation at startup, which is the correct outcome but a
confusing one to debug if you registered it by reflex.

Don't: look for `registerStandardConfigs` or an `AddInfra(...)` helper. The
composition IS the API — one line per block, visible in the service, so the root
schema a service validates against is readable in one place.

## The four presets

| block      | shape                                                               | durability                                    |
| ---------- | ------------------------------------------------------------------- | --------------------------------------------- |
| `postgres` | `host port database username password ssl pool{min,max}`            | durable                                       |
| `cache`    | `host port password db tls`                                         | RAM-backed, **ephemeral** (Dragonfly)         |
| `kv`       | `host port password db tls`                                         | **persistent** (Upstash / snapshot Dragonfly) |
| `storage`  | `endpoint region bucket accessKeyId secretAccessKey forcePathStyle` | durable object storage                        |

These key sets are **C0-frozen** and matched key-for-key by the bun and dotnet
standard-config siblings. Adding, renaming, or dropping a key is a
cross-language contract change.

`cache` and `kv` have identical connection fields because both speak the Redis
protocol. They are still separate blocks pointing at separate instances.

Don't: point `cache` and `kv` at one instance to save a container. A cache
eviction then silently drops durable state, and the test that "passed" was
testing a deployment that does not exist.

## Keyed multi-instance, and the key contract

Every preset is a keyed map, so a second Postgres pool or a second bucket is a
YAML entry and nothing else:

```yaml
postgres:
  MAIN:
    host: primary.lapras.invalid
    # …
  REPLICA:
    host: replica.lapras.invalid
    # …
```

Connection names are **authored UPPERCASE** (R14). Check authored names with
`standardconfig.ValidKey`.

The contract has a second half, and this is the part that surprises people: the
config loader **canonicalizes key spelling**, so a block authored with `MAIN`
arrives decoded as `main`.

Do: resolve connections with `standardconfig.Named(problems, block, "MAIN")`. It
matches case-insensitively for exactly this reason, and a missing name is a
problem-typed error naming the connections that do exist.

Don't: index the decoded map directly with the authored name (`block["MAIN"]`).
It returns a zero entry, and the failure surfaces much later as a dial to host
`""`.

Don't: assert UPPERCASE on a decoded block — every real document would fail.
Call `standardconfig.ValidateKeys(problems, blockKey, block)` instead. It
enforces what survives loading: a connection name must be an identifier, or its
`<PREFIX>POSTGRES__<NAME>__PASSWORD` override path is unreachable and its secret
can never be injected.

The preset fragments deliberately carry no `patternProperties` or
`propertyNames`. The config library rejects both as authoring faults, because
they constrain the authored spelling of a key that it matches canonically.

## Secrets

Secrets — the Postgres and Redis passwords, the storage credentials — are
ordinary config keys, blank in committed YAML, injected per landscape through
the environment tier (R14/M33):

```bash
ATOMI_STORAGE__ASSETS__SECRETACCESSKEY=...
```

Do: leave them as `""` in every YAML layer. The schemas carry no `minLength` on
a secret precisely so the committed document stays valid against its own schema.

Don't: put a placeholder value in YAML. A blank environment value is _unset_
(M33), so a placeholder survives the merge and reaches the driver.

## TestHelper

```go
started, err := testhelper.StartPostgres(ctx, testhelper.PostgresOptions{Key: "MAIN"})
pg := testhelper.RequireStarted(t, started, err)
t.Cleanup(func() { _ = pg.Terminate(ctx) })

// pg.Block is a keyed postgres block valid against the preset schema.
```

- `StartPostgres`, `StartCache`, `StartKv`, `StartStorage` boot a real container
  AND emit the matching schema-valid block. `StartStorage` also creates the
  bucket, because MinIO does not create one on boot.
- `CreateBucket` adds further buckets to an endpoint a start helper returned.
- `FakePostgres`, `FakeCache`, `FakeKv`, `FakeStorage` are container-free blocks
  for unit tiers: deterministic values, blank secrets, UPPERCASE keys.
- `RequireStarted`, `RequireEntry`, `RequireUppercaseKeys`,
  `RequireConnectionNames` are the assertions; they take the minimal `TestingT`,
  so they work with anything exposing `Helper` and `Fatalf`.
- `Runtime` is the container seam. Inject a stub to drive failure paths without
  Docker; the default `DockerRuntime` talks to the ambient daemon.

Do: use `StartCache` and `StartKv` when a test needs both — two containers, as
in production.

Don't: reach for the start helpers in a unit tier. That is what the fakes are
for; containers belong to the integration tier.
