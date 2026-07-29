---
name: diene-dotnet-config-usage
description: Load, merge, and validate layered service configuration with AtomiCloud.Diene.Config, and fake those layers in tests with its TestHelper.
---

# Diene .NET Config usage

The one library that loads config layers, merges them, and validates the
composed root. If you are reaching for a second config mechanism, stop.

## Wire it up

Declare the three layers and register your blocks. The env prefix is required —
the library bakes no default, because the prefix belongs to your app.

```csharp
builder.Configuration.AddAtomiConfig(new AtomiConfigSource
{
    BaseFile = "Config/settings.yaml",             // required, FULL defaults
    LandscapePattern = "Config/settings.{0}.yaml", // optional sparse overlay
    Landscape = landscape,                         // blank reads the LANDSCAPE variable
    EnvPrefix = "ATOMI_",                          // yours to choose
});

builder.Services.AddAtomiServiceTree();                                   // the mandatory App block
builder.Services.RegisterOption<OtelOption, OtelOptionValidator>("Otel");  // one line per block
```

Precedence is base, then landscape overlay, then environment. That ordering is
`IConfiguration` provider ordering, not a merge engine, so validation naturally
runs on the FINAL merged layer only, at `ValidateOnStart`.

## Key spelling does not matter

`error_portal`, `error-portal`, `errorPortal`, and `ErrorPortal` are one key.
Author YAML in snake_case and options in Pascal; they meet in the middle.

```yaml
error_portal:
  signing_key: # blank: injected from the environment
  retry_hosts:
    - docs-1.atomi.cloud
```

```bash
ATOMI_ERROR_PORTAL__SIGNING_KEY=...    # __ nests
ATOMI_ERROR_PORTAL__RETRY_HOSTS__0=... # lists use INDEXED KEYS
```

## Do

- Put every key in the base layer, including the ones only the environment ever
  fills. A key that exists nowhere binds to a default and fails silently.
- Keep overlays sparse; name only what differs.
- Declare secrets blank in YAML. They are ordinary config keys and nothing
  special-cases them.
- Validate with FluentValidation (`RegisterOption<T, TValidator>`). Reserve the
  DataAnnotations overload for blocks too trivial to deserve a validator.
- Export your engine's block schema next to the code that reads it and let the
  service compose it. Only `standard-config` owns infra presets.

## Do not

- Do not encode lists as JSON or comma-separated strings in environment
  variables. Indexed keys are the contract.
- Do not hardcode a prefix inside a library. It is an app-level decision.
- Do not expect hot reload. `ReloadOnChange` is refused in v1, deliberately.
- Do not write config files at boot. Schema generation is a dev and CI task.
- Do not add a second YAML reader or a deep-merge helper. Provider layering is
  the merge and the configuration binder owns environment coercion.

## Generated schema

Every config YAML carries a `$schema` pointer on its first line, and CI reds on
drift. Generate from a task and verify in CI:

```csharp
ConfigSchemaGen.WriteSchema(registry, path);  // Result<Unit, SchemaGenError>
ConfigSchemaGen.VerifySchema(registry, path); // Drift, Missing, or Io
```

The root pointer is not a config key; the provider skips it.

## Testing with AtomiCloud.Diene.Config.TestHelper

Fake the layers instead of writing files. The fixture keys itself exactly as the
real providers do, so a test that passes here passes in production.

```csharp
var config = new AtomiConfigFixture()
    .WithBase("error_portal:host", "base")
    .WithLandscape("error_portal:host", "landscape")
    .WithEnvironment("ERROR_PORTAL__HOST", "environment")
    .Build();

config.Should().HaveValue("error_portal:host", "environment");
config.Should().HaveBlankValue("error_portal:signing_key");
config.Should().HaveList("error_portal:retry_hosts", "one", "two");
```

Prove fail-fast as a value rather than an exception:

```csharp
var result = new AtomiConfigFixture()
    .WithBase("error_portal:host", "")
    .Resolve<ErrorPortalOption>(s =>
        s.RegisterOption<ErrorPortalOption, ErrorPortalOptionValidator>("ErrorPortal"));

result.IsFailure(out var message).Should().BeTrue();
```

`WithSecret(key, environmentName, value)` declares a key blank and injects it,
covering the whole secrets convention in one call. `FakeConfigLayer` is there
for when you need to place a fake layer at a position of your own choosing.

The TestHelper assembly is test infrastructure: measure it through the meta
tier, never the unit ledger. When you extend it, add both a known-good and a
known-bad case for every assertion.

For package lifecycle, identity, coverage, and promotion rules, read
`docs/developer/dotnet-lib-baseline.md` in the source repository.
