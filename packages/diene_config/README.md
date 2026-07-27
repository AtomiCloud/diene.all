# diene_config

[![pub package](https://img.shields.io/pub/v/diene_config.svg)](https://pub.dev/packages/diene_config)
[![CI](https://github.com/AtomiCloud/diene.dart_config/actions/workflows/ci.yaml/badge.svg)](https://github.com/AtomiCloud/diene.dart_config/actions/workflows/ci.yaml)
[![unit coverage](https://codecov.io/gh/AtomiCloud/diene.dart_config/graph/badge.svg?flag=unit)](https://codecov.io/gh/AtomiCloud/diene.dart_config)
[![meta coverage](https://codecov.io/gh/AtomiCloud/diene.dart_config/graph/badge.svg?flag=meta)](https://codecov.io/gh/AtomiCloud/diene.dart_config)

Layered, immutable configuration for Dart and Flutter applications. A full base
YAML is overlaid by a sparse flavor/landscape YAML, then an optional development
override, then `--dart-define` values **last** — and the merged tree is validated
**once**, against a root schema the service composes from engine-owned blocks.

```dart
import 'dart:async';

import 'package:diene_config/diene_config.dart';

final class ApiSettings {
  const ApiSettings(this.baseUrl);
  final Uri baseUrl;
}

final apiBlock = ConfigBlock<ApiSettings>(
  key: 'api',
  decode: (values) => ApiSettings(Uri.parse(values['baseUrl']! as String)),
);

Future<void> main() async {
  final loaded = await ConfigLoader(
    base: YamlConfigSource.string(
      'api:\n  baseUrl: https://api.example.test',
      name: 'base.yaml',
    ),
    dartDefines: const DartDefineOverrides(
      prefix: 'MY_APP_',
      values: {
        'MY_APP_API__BASE_URL': String.fromEnvironment('MY_APP_API__BASE_URL'),
      },
    ),
    schema: ConfigSchema(blocks: [apiBlock]),
  ).load();

  final api = loaded.unwrap().slice(apiBlock);
  print(api.baseUrl);
}
```

## What it owns — and what it doesn't

It owns YAML reading, layer orchestration, schema composition, final validation,
typed slices, and the landscape accessor.

It owns **no merge engine**: `deepMerge`, `canonicalConfigKey`,
`environmentToNestedMap`, and `stableConfig` come from the published
[`diene_core_utils`](https://pub.dev/packages/diene_core_utils). And it owns **no
engine's schema**: auth and API engines export their own `ConfigBlock` values,
and the application composes them.

## Failures are values

`load()` returns `Future<Result<DieneConfig>>` and never throws for a
configuration error. Failures carry the RFC 9457 `Problem` envelope from
[`diene_problems`](https://pub.dev/packages/diene_problems), with codes
`source_unreadable`, `source_not_a_map`, `schema_invalid` — whose `data.errors`
lists **every** problem found in one pass — and `landscape_missing`.

Throwing is reserved for programmer misuse: a duplicate block key, or a slice
for a block that was never composed.

## Defines and indexed lists

Lists come only from contiguous indexed keys (`MY_APP_AUTH__SCOPES__0`,
`__1`, …). JSON-in-define and comma-separated encodings are deliberately never
decoded. Blank values are unset and cannot erase a base value. Key matching
ignores case, hyphens, and underscores on both prefix and path; the base layer's
spelling wins.

## Landscape

The store track supplies identity via
`--dart-define=DIENE_LANDSCAPE=lapras`. `landscape()` is an accessor only — it
never detects identity from a hostname or runtime state.

## TestHelper

```dart
import 'package:diene_config/test_helper.dart';
```

Dependency-light fakes, builders, and assertions: `FakeConfigSource`,
`FailingConfigSource`, `FakeLandscapeSource`, `ConfigStubBuilder`,
`FakeConfigHarness`, `expectOkConfig`, `expectErrConfig`,
`assertConfigProblem`, `assertConfigSlice`. It imports no test framework, so it
works under any runner and adds nothing to a consumer's runtime graph.

## Migrating from an in-app `config/app_config.dart`

Swap one import — `package:diene_config/config/app_config.dart` — instead of
every call site. See [the package doc](doc/configuration.md#migrating-from-an-in-app-configapp_configdart).

## More

[The configuration doc](doc/configuration.md) covers the full contract, the
problem catalog, C0 §3 conformance, TestHelper usage, and deliberate parity
deltas versus the Bun sibling.

## Development

- `pls setup` resolves the workspace dependencies.
- `pls test` runs the unit, C0 conformance, and TestHelper meta suites.
- `pls test:coverage` enforces the separate unit and meta ledgers.
- `pls deadcode` runs the repository and production-only dead-code passes.
- `pls package:validate` runs the release guard, publish dry-run, and pana.
