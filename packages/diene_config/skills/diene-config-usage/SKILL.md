---
name: diene-config-usage
description: Use when consuming package:diene_config — loading layered YAML configuration, composing engine-owned ConfigBlock schemas, reading typed slices or the landscape, handling its Result/Problem failures, or testing with its dependency-light TestHelper.
---

# diene_config usage

Import the public barrel; never reach into `lib/src`:

```dart
import 'package:diene_config/diene_config.dart';
```

Read `doc/configuration.md` from the installed package before changing
configuration code.

## The ladder

Layer order is fixed: full base YAML → one sparse flavor/landscape overlay →
optional development hook → `--dart-define` values LAST → validate once.

```dart
final Result<DieneConfig> loaded = await ConfigLoader(
  base: YamlConfigSource(name: 'config/base.yaml', read: readBaseYaml),
  overlay: YamlConfigSource(name: 'config/$track.yaml', read: readTrackYaml),
  dartDefines: const DartDefineOverrides(
    prefix: 'ACME_',
    values: <String, String>{
      'ACME_API__BASE_URL': String.fromEnvironment('ACME_API__BASE_URL'),
    },
  ),
  schema: ConfigSchema(blocks: <ConfigBlockSchema>[apiBlock, authBlock]),
).load();
```

- The base document must be **full** — every overrideable path with a default.
  Overlays are sparse.
- Validation runs **once**, on the final tree. Do not pre-validate a layer; a
  base that is incomplete alone is fine if a later layer completes it.
- `read` is a callback, so the package needs no `dart:io` or Flutter. Pass
  `rootBundle.loadString` in Flutter, `File(path).readAsString` in pure Dart.

## Schemas belong to their owners

Compose `ConfigSchema` from `ConfigBlock<T>` values that engines export beside
the code reading them, plus the service's own. **Never** recreate an engine's
schema in the app, and never add an engine block to `diene_config`.

```dart
final ConfigBlock<ApiSettings> apiBlock = ConfigBlock<ApiSettings>(
  key: 'api',
  decode: (Map<String, Object?> values) => ApiSettings(...),  // throw to reject
);
```

A decoder **throws** to reject its input; the schema catches it and folds it
into one aggregate failure. Mark a block `required: false` when it may be
absent, and read it with `optionalSlice` / `hasSlice`.

## Defines

Set a per-app prefix. Use `__` for nesting and contiguous indexed keys for
lists (`ACME_AUTH__SCOPES__0`, `__1`, …). Never encode a list as JSON or as a
comma-separated string — neither is decoded. Blank values are UNSET and cannot
erase a base value. Key matching ignores case, hyphens, and underscores on both
prefix and path; the base layer's spelling wins.

## Landscape

`landscape()` is an ACCESSOR for the `DIENE_LANDSCAPE` store-track define,
returning `Result<String>`. Never detect the landscape from a hostname or
runtime state. Inject `FakeLandscapeSource` in tests.

## Failures are values

`load()` returns `Future<Result<DieneConfig>>` and does not throw for a
configuration error. Match on it:

```dart
loaded.match(
  ok: (DieneConfig config) => runApp(config),
  err: (Problem problem) => reportStartupFailure(problem),
);
```

Codes: `source_unreadable`, `source_not_a_map`, `schema_invalid` (its
`data.errors` lists **every** problem found), `landscape_missing`. A malformed
define key arrives as the `diene_core_utils` coercion envelope unchanged — use
`configProblemCode(problem)`, which returns `None` for a foreign envelope,
rather than reading `data['code']` directly.

`StateError` / `ArgumentError` mean programmer misuse (a duplicate block key, a
slice never composed), not a configuration problem. Do not catch them; fix the
call.

## TestHelper

```dart
import 'package:diene_config/test_helper.dart';
```

Ships `FakeConfigSource`, `FailingConfigSource`, `FakeLandscapeSource`,
`ConfigStubBuilder`, `FakeConfigHarness`, and the `expectOkConfig` /
`expectErrConfig` / `assertConfigProblem` / `assertConfigSlice` assertions. It
imports no test framework, so it works under any runner; failures throw
`ConfigAssertionFailure`.

- Use `ConfigStubBuilder` so a stub passes through the real schema and cannot
  be shaped like a configuration the loader would reject.
- Use `FakeConfigHarness` for the full ladder in memory — it drives the real
  `ConfigLoader`.
- Use `FailingConfigSource` to cover the error path without a filesystem.

See `patterns.md` for schema composition, the migration entrypoint, and the
meta-test convention.
