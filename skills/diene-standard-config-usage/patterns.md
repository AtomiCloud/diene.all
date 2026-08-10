# standard-config patterns

Copyable recipes for consuming `@atomicloud/diene.standard-config`. The library
ships preset SCHEMAS only; `@atomicloud/diene.config` does all loading and
validation.

## Do

- **Compose, don't re-declare.** A new service registers the presets it needs
  instead of hand-writing the same postgres/cache/kv/storage blocks (the nitroso
  pattern, made a library).

  ```ts
  const registry = registerStandardConfigs(ConfigRegistry.create(), {
    which: ['postgres', 'cache', 'kv', 'storage'] as const,
  });
  ```

- **Add an instance in YAML.** Two Postgres pools = two keyed entries; the schema
  never changes.

  ```yaml
  postgres:
    MAIN: { host: db, port: 5432, database: app, username: app, password: '', ssl: true, pool: { min: 0, max: 10 } }
    REPLICA:
      { host: replica, port: 5432, database: app, username: ro, password: '', ssl: true, pool: { min: 0, max: 5 } }
  ```

- **Keep secrets blank in YAML.** Inject per landscape via the env tier:
  `ATOMI_POSTGRES__MAIN__PASSWORD=…` (double-underscore nesting, prefix set by
  the app). A blank env value leaves the field unset (M33).

- **Look up connections fail-fast.** `named(config('postgres'), 'MAIN')` throws a
  clear error listing known keys instead of returning `undefined`.

- **Fake block storage in unit tiers, boot a container in int tiers.**
  `InMemoryBlockStorage` for units; `startStorage()` + `S3BlockStorage` for ints.

## Don't

- **Don't relabel a cache as a kv.** They share the Redis protocol but are
  separate blocks: cache is ephemeral (Dragonfly), kv is persistent (snapshot
  durability). Pick the block whose durability contract you need.

- **Don't lowercase connection keys.** `main` fails validation; pool names are
  UPPERCASE (R14).

- **Don't expect this lib to load config.** It has no loader/merger/validator —
  compose its presets into a `lib/bun/config` registry and let config validate.

- **Don't put otel/auth/http here.** Those are engine-owned blocks; import them
  from their engine lib and register them alongside these infra presets.

- **Don't run `S3BlockStorage` off Bun.** It uses `Bun.S3Client`; under Node,
  use the in-memory fake instead.
