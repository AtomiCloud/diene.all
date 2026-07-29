---
name: diene-dotnet-standard-config-usage
description: Compose the four frozen infra config presets — postgres, cache, kv, storage — with AtomiCloud.Diene.StandardConfig, and boot real dependencies for tests with its TestHelper.
---

# Diene .NET StandardConfig usage

Four infra presets, a tiny block-storage surface, and Testcontainers glue.
This library ships **schemas**, never a loader: `AtomiCloud.Diene.Config` is the
sole merger and validator, and engine blocks (otel, auth, http) belong to their
own engine libraries. If you are about to hand-write a `postgres:` block, stop.

## Compose the presets you need

One line. The config lib binds each block, validates it at `ValidateOnStart`,
and records it in the schema registry behind your generated `$schema` pointer.

```csharp
builder.Services.AddStandardConfigs(
    StandardConfigPreset.Postgres | StandardConfigPreset.Cache | StandardConfigPreset.Storage);

// or one at a time
builder.Services.AddPostgresPreset().AddCachePreset();
```

Then resolve the named block type:

```csharp
public sealed class Repository(IOptions<PostgresBlock> postgres)
{
    private readonly PostgresOption _main = postgres.Value.Named("MAIN");
}
```

## The four frozen blocks

C0 §3 freezes these key sets family-wide — bun, .NET, and Go match key for key.
Do not add, rename, or drop a key without a C0 change.

```yaml
postgres:
  MAIN: { host: db.internal, port: 5432, database: app, username: app, password: , ssl: true, pool: { min: 0, max: 10 } }
cache:                       # Dragonfly. RAM-backed, EPHEMERAL.
  MAIN: { host: cache.internal, port: 6379, password: , db: 0, tls: false }
kv:                          # PERSISTENT. Same protocol, different durability contract.
  MAIN: { host: kv.internal, port: 6379, password: , db: 0, tls: true }
storage:
  MAIN: { endpoint: https://fly.storage.tigris.dev, region: auto, bucket: app, access_key_id: , secret_access_key: , force_path_style: false }
```

**Do not point `kv` at your `cache` instance.** They speak the same protocol on
purpose and differ on the only thing that matters: cache may vanish, kv may not.
The two-preset split exists to make that swap impossible to do by accident.

Secrets are blank in YAML and injected per landscape through the ordinary env
override path — `ATOMI_POSTGRES__MAIN__PASSWORD`. Nothing about them is special.

## Keyed multi-instance: a second connection is YAML

Every preset is a map of NAMED connections. Adding one is data, never code:

```yaml
postgres:
  MAIN: { host: primary.internal, ... }
  REPLICA: { host: replica.internal, ... }   # no new type, no new registration
```

```csharp
var replica = postgres.Value.Named("REPLICA");        // throws, naming known keys
var maybe = postgres.Value.Find("ANALYTICS");         // Option<PostgresOption>
```

### Author names UPPERCASE — and gate it

R14 requires UPPERCASE pool names, but .NET cannot enforce that at runtime: the
config lib folds key casing before the binder ever sees it, so `MAIN` and `main`
are indistinguishable by the time you hold a block. Lookups are therefore
case-insensitive, and the contract is gated on the **source** instead:

```csharp
[Fact]
public void Config_names_every_connection_in_uppercase() =>
    PresetYamlAudit.ShouldUseUppercaseConnectionNames("Config", "settings*.yaml");
```

Add that one test to your service. Without it nothing catches lowercase drift.

## Object storage

The whole interface is three members. That is deliberate.

```csharp
using var storage = S3BlockStorage.Create(storageBlock.Named("MAIN"));

var saved = await storage.SaveAsync(new SaveInput
{
    Key = "avatars/user-1.png",
    Body = bytes,
    ContentType = "image/png",
});

saved.Match(
    stored => logger.LogInformation("stored at {Link}", stored.Link),
    error => logger.LogWarning("upload failed: {Error}", error));

var link = storage.GetLink("avatars/user-1.png");                         // pure
var signed = storage.GetSignedUrl("avatars/user-1.png",
    new SignedUrlOptions { ExpiresIn = TimeSpan.FromMinutes(5) });        // pure
```

`SaveAsync` is railway-oriented — transport failures come back as
`Err<StorageError>`. Programming errors still throw; do not treat an escaping
exception as a retryable upload.

## Testing

### Unit tiers: use the fake

```csharp
var storage = new InMemoryBlockStorage();
await storage.SaveAsync(new SaveInput { Key = "a.txt", Body = bytes });

storage.Has("a.txt").Should().BeTrue();
storage.Read("a.txt").IsSome(out var blob).Should().BeTrue();
```

The fake is not a guess about S3: this package's meta tier runs ONE shared
`BlockStorageContract` suite against both the fake and the real adapter over
MinIO, so behaviour you rely on is behaviour both are held to. Run it against
your own `IBlockStorage` too:

```csharp
await BlockStorageContract.VerifyAsync(myImplementation);
```

### Integration tiers: boot the real thing

Each helper starts a container **and** emits the schema-valid, keyed block that
reaches it — including creating the storage bucket, which is the step everyone
forgets.

```csharp
await using var postgres = await StandardConfigContainers.StartPostgresAsync();
await using var minio = await StandardConfigContainers.StartStorageAsync(
    new StartStorageOptions { Bucket = "uploads" });

// feed them through the REAL config path rather than around it
var configuration = new ConfigurationBuilder()
    .AddInMemoryCollection(postgres.ConfigurationValues(PostgresOption.Key))
    .Build();
```

`StartCacheAsync` and `StartKvAsync` cover the Redis-protocol presets; each
takes a `Key` so you can start `REPLICA` or `SESSIONS` instead of `MAIN`.

### Asserting on a block

```csharp
block.ShouldAsPresetBlock()
    .HaveConnection("MAIN").Which.Port.Should().Be(5432);

block.ShouldAsPresetBlock().BeValidAgainst(new PostgresBlockValidator());
```

It is `ShouldAsPresetBlock()`, not `Should()`, on purpose — a block binds as a
`Dictionary<string, TEntry>`, and shadowing FluentAssertions' own dictionary
assertions would hide the ones you also want.

## Do not

- **Do not** load or merge YAML here — that is `AtomiCloud.Diene.Config`, alone.
- **Do not** register an otel, auth, or http block from this package. Engine
  libraries export their own config blocks; services compose them.
- **Do not** reference `Dictionary<string, PostgresOption>` where `PostgresBlock`
  belongs. The named type is what the schema registry can render — an anonymous
  dictionary produces a dangling `$ref` and schema generation fails.
- **Do not** integration-test object storage in your own repo. It is proven here.
