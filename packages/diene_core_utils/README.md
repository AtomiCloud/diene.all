# diene_core_utils

Pure Dart utilities for deterministic identity strings, layered configuration,
and canonical date/time wire formats.

Every fallible member returns `Result` from
[`diene_result`](https://pub.dev/packages/diene_result) carrying an RFC 9457
`Problem` from [`diene_problems`](https://pub.dev/packages/diene_problems).
Nothing here throws to report an expected failure, so callers never wrap a
utility call in `try`/`catch`.

The package is platform-neutral: it imports neither `dart:io` nor Flutter, and it
reaches the filesystem only through the injected `Vfs` interface from
[`diene_interfaces`](https://pub.dev/packages/diene_interfaces). It runs unchanged
on the Dart VM, on the web, and in Flutter.

## Install

```sh
dart pub add diene_core_utils
```

## Identity strings

```dart
import 'package:diene_core_utils/diene_core_utils.dart';

slugify('Crème Brûlée'); // 'creme-brulee'  — NFKD folds the marks, keeps the letters
slugify('  --Hello World--  '); // 'hello-world'

namespacedKey('Diene', 'Core Utils').match(
  ok: (String key) => key, // 'diene:core-utils'
  err: (Problem problem) => problem.title,
);
```

## Layered configuration (C0 §3)

Deep-merge layers lowest-precedence-first. Key matching is case- and
separator-insensitive, so an environment override lands on the YAML key it means
even when the two are spelled differently.

```dart
final JsonObject base = <String, Object?>{
  'app': <String, Object?>{'displayName': 'base', 'retries': 1},
};

final Result<JsonObject> defines = environmentToNestedMap(
  <String, String>{
    'ACME_APP__DISPLAY_NAME': 'production', // snake → displayName
    'ACME_APP__TAGS__0': 'first',           // __<digits> builds a list
    'ACME_APP__RETRIES': '',                // blank means UNSET, not null
  },
  prefix: 'ACME_',
);

final JsonObject merged = deepMergeAll(<JsonObject>[base, defines.unwrap()]);
// {app: {displayName: production, retries: 1, tags: [first]}}
```

Lists come only from indexed keys: neither a JSON string nor a comma-separated
string is ever decoded into a collection.

`stableConfig` gives you a deterministic projection — keys sorted at every depth,
list order preserved — so a merged configuration is safe to hash, diff, or use as
a cache key. Circular input is reported as a `Problem` rather than recursing
forever.

## Date and time wire formats (C0 §1)

```dart
WireDate.parse('2026-07-26');   // Ok
WireDate.parse('2026-02-30');   // Err — validated against the real calendar
WireTime.parse('23:59:59');     // Ok
IsoDuration.parse('P1DT2.5H');  // Ok — kept verbatim, never converted
IanaTimezone.parse('Asia/Singapore'); // Ok
IanaTimezone.parse('PST');      // Err — an abbreviation, not an IANA id
```

Timezone validation is exact membership in a **vendored, digest-pinned IANA
release** (`2026b`, 598 identifiers), so the answer does not change with whatever
tzdata the host happens to carry.

Instants have exactly ONE canonical spelling:

```dart
parseRfc3339Utc('2026-07-26T01:02:03Z');      // Ok
parseRfc3339Utc('2026-07-26T01:02:03+00:00'); // Err — same instant, wrong spelling
normalizeRfc3339ToUtc('2026-07-26T09:02:03+08:00');
// Ok('2026-07-26T01:02:03.000Z') — use this at the boundary
```

Rejecting `+00:00` is deliberate. Fixing one spelling is what lets two services
compare wire bytes instead of parsing to compare; offsets are normalised once, on
the way in.

Prefer injecting a single object? `const WireCodec()` exposes the whole temporal
vocabulary.

## Configuration from a filesystem

```dart
import 'package:diene_interfaces/diene_interfaces.dart';

final Result<JsonObject> config = await loadConfigLayers(vfs, <ConfigLayer>[
  ConfigLayer(path: '/etc/acme/base.yaml', parse: myYamlReader),
  ConfigLayer(
    path: '/etc/acme/production.yaml',
    parse: myYamlReader,
    optional: true, // an absent overlay contributes nothing; it is not an error
  ),
]);
```

`parse` is yours because this package ships no YAML or JSON parser: the format is
your choice, while the precedence and merge semantics live here. A `Vfs` failure
comes back unchanged, so its status and `recoverable` flag survive.

Because `Vfs` is an interface, the same code is testable with the fakes
`diene_interfaces` already ships:

```dart
import 'package:diene_interfaces/test_helper.dart';

final InMemoryVfs vfs = InMemoryVfs();
await writeVfsText(vfs, '/etc/acme/base.yaml', 'name: test');
```

## Bounded concurrency

```dart
final Result<List<Response>> responses = await mapWithConcurrency(
  urls,
  4, // at most four in flight; work is pulled, not pushed
  fetch,
);
```

Results keep INPUT order regardless of completion order, and the lowest failing
index wins, so the outcome never depends on timing.

## Sub-libraries

- `package:diene_core_utils/diene_core_utils.dart` — everything above.
- `package:diene_core_utils/c0_temporal.dart` — `c0TemporalContract`, the shared
  version-pinned C0 §1 temporal vectors. Other Diene Dart packages drive their own
  conformance tests from this single value rather than restating cases.

## Documentation

`doc/core_utils.md` in this package carries the full member table, the rationale
behind each design choice, and the deliberate deltas versus the TypeScript
sibling. The shipped `diene-core-utils-usage` skill covers agent-facing usage
patterns.

## License

MIT — see `LICENSE`.
