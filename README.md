# diene_config

Layered, immutable configuration for Dart and Flutter applications. The loader
applies full base YAML, a sparse flavor or landscape overlay, an optional
development override, and `--dart-define` values last. It validates only the
final merged tree against a root schema composed by the service from
engine-owned blocks.

```dart
import 'package:diene_config/diene_config.dart';

final class ApiSettings {
  const ApiSettings(this.baseUrl);
  final Uri baseUrl;
}

final apiBlock = ConfigBlock<ApiSettings>(
  key: 'api',
  decode: (values) => ApiSettings(Uri.parse(values['baseUrl']! as String)),
);

final config = await ConfigLoader(
  base: YamlConfigSource(
    name: 'config/base.yaml',
    read: () => rootBundle.loadString('config/base.yaml'),
  ),
  overlay: YamlConfigSource(
    name: 'config/${landscape()}.yaml',
    read: () => rootBundle.loadString('config/${landscape()}.yaml'),
  ),
  dartDefines: DartDefineOverrides(
    prefix: 'MY_APP_',
    values: const {
      'MY_APP_API__BASE_URL': String.fromEnvironment(
        'MY_APP_API__BASE_URL',
      ),
    },
  ),
  schema: ConfigSchema(blocks: [apiBlock]),
).load();

final api = config.slice(apiBlock);
```

Lists use indexed keys such as `MY_APP_AUTH__SCOPES__0` and
`MY_APP_AUTH__SCOPES__1`. JSON-in-environment and comma-separated list
encodings are deliberately unsupported. Empty define values are unset.

The store track supplies identity with
`--dart-define=DIENE_LANDSCAPE=lapras`; `landscape()` is an accessor only and
never detects identity from a hostname or runtime environment.

See [the configuration standard](doc/configuration.md) for the full
contract, typed schema composition, TestHelper usage, and Bun-family parity
notes.
