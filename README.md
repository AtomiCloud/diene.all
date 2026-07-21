# diene_core_utils

[![CI](https://github.com/AtomiCloud/diene.dart_core-utils/actions/workflows/ci.yaml/badge.svg)](https://github.com/AtomiCloud/diene.dart_core-utils/actions/workflows/ci.yaml)
[![codecov](https://codecov.io/gh/AtomiCloud/diene.dart_core-utils/graph/badge.svg)](https://codecov.io/gh/AtomiCloud/diene.dart_core-utils)
[![pub package](https://img.shields.io/pub/v/diene_core_utils.svg)](https://pub.dev/packages/diene_core_utils)

Pure, frontend-safe Dart utilities shared by the Diene package family:

- NFKD-to-kebab slugs and validated namespaced keys
- immutable deep merge and environment-path coercion
- `sleep` using Dart `Duration`
- C0 date, time, RFC 3339 UTC instant, ISO 8601 duration, and IANA timezone codecs

```dart
import 'package:diene_core_utils/diene_core_utils.dart';

final NamespacedKeyResult key = namespacedKey('Mobile App', 'Current User');
final String display = key.match(valid: (value) => value, invalid: (error) => '$error');

final JsonObject override = environmentToNestedMap(
  {'ATOMI_AUTH__SCOPES__0': 'openid'},
  prefix: 'ATOMI_',
);
final JsonObject config = deepMerge(baseConfig, override);
```

See [the core-utils standard](doc/core_utils.md) for the complete
API, wire constraints, testing policy, and Bun-family parity deltas.

## TestHelper verdict

This package intentionally ships no `test_helper.dart`: its functions are pure,
and stock equality/assertions are sufficient. The installed
`diene-core-utils-usage` skill contains the exact opt-in procedure if a future API
adds a consumer seam or genuinely repeated assertion.
