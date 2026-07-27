# diene_config

`diene_config` owns configuration **mechanics**: layer loading, one final
validation pass, typed slice access, and the landscape accessor. It owns no
auth, API, telemetry, or service schema. Each engine exports its own
`ConfigBlock<T>` beside the code that reads it; the application composes those
blocks, with its own, into one `ConfigSchema`.

It also owns no merge engine. `deepMerge`, `deepMergeAll`, `canonicalConfigKey`,
`coerceEnvironmentScalar`, `environmentToNestedMap`, and `stableConfig` come
from the published `diene_core_utils`. A private copy here would be a second
implementation of C0 §3, and a second thing to drift.

## Layer order

1. A full **base** YAML defines every overrideable path and its default.
2. One sparse **flavor/landscape** YAML overlays the base.
3. An optional **development** source provides a controlled local hook.
4. Enumerated **`--dart-define`** values apply last.
5. The service-composed schema validates the final tree **once**.

No intermediate layer is validated and none is ever exposed. A base document
that is invalid on its own — a deliberately impossible default, a key only the
overlay supplies — is correct as long as the final merged tree validates.

Configuration is immutable after loading. There is no watch or reload API.

Flutter callers normally pass `rootBundle.loadString`; pure Dart callers pass
`File(path).readAsString`. The package imports neither Flutter nor `dart:io`, so
it runs unchanged on the VM, on the web, and in Flutter.

## Failures are values

Every expected failure is an `Err` carrying the RFC 9457 `Problem` envelope from
`diene_problems`. `ConfigLoader.load` returns `Future<Result<DieneConfig>>` and
never throws for a configuration error.

| Code | Status | Cause |
| --- | --- | --- |
| `source_unreadable` | 422 | a layer's read callback threw, or its YAML did not parse |
| `source_not_a_map` | 422 | a layer parsed but its root is not a map |
| `schema_invalid` | 422 | the final merged tree failed validation |
| `landscape_missing` | 400 | no `DIENE_LANDSCAPE` define was supplied |

`schema_invalid` collects **every** problem in one pass — its `data.errors`
lists all of them, so one deploy fixes a whole misconfiguration rather than the
first line of it.

A malformed `--dart-define` key is reported with the `diene_core_utils`
coercion envelope **unchanged** (`data.util == 'coercion'`), because re-minting
it under a config code would replace a precise vocabulary with a vaguer one.
Use `configProblemCode(problem)` to tell the two apart: it returns `None` for an
envelope this package did not mint.

Throwing is reserved for programmer misuse, where the input is source code
rather than data: a duplicate or empty block key (`ArgumentError`), a slice for
a block that was never composed (`StateError`), and a `ConfigBlock.decode`
callback rejecting its own input — which `ConfigSchema.validate` catches and
folds into the aggregate `schema_invalid` problem.

## Defines and indexed lists

The prefix is required and application-owned; `ACME_` is only an example.
Matching ignores case, hyphens, and underscores on **both** the prefix and the
path, so `ACME_APP_SETTINGS__DISPLAY_NAME`, `acme_app-settings__display-name`,
and `AcMe_AppSettings__DisplayName` all reach a YAML key spelled `displayName`.
The base layer's spelling always wins as the output key.

`__` separates path components. Lists use contiguous indexed keys:

```text
ACME_AUTH__SCOPES__0=openid
ACME_AUTH__SCOPES__1=offline_access
```

The indexed keys replace the YAML list wholesale — C0 §3 has no append
semantics. JSON and comma encodings are never decoded; such a value stays the
string it is. Blank values are UNSET and cannot erase a base-layer value.
Scalars coerce to booleans, safe integers, and decimals; everything else stays a
string for the owning block decoder to validate.

Dart has no runtime environment enumeration — `String.fromEnvironment` is a
compile-time lookup of a literal key — so an application **enumerates** the
defines it accepts:

```dart
dartDefines: const DartDefineOverrides(
  prefix: 'ACME_',
  values: <String, String>{
    'ACME_API__BASE_URL': String.fromEnvironment('ACME_API__BASE_URL'),
  },
),
```

## Landscape accessor

`landscape()` reads the build-time `DIENE_LANDSCAPE` define and returns
`Result<String>`. A mobile store track **is** the landscape. The accessor
performs no hostname sniffing, no runtime environment lookup, and no remote
detection — the value is a compile-time constant and physically cannot change at
runtime. A blank or whitespace-only define is ABSENT, not the empty landscape,
matching the blank-is-unset rule that governs every other define. Landscape is
identity, never a secret. Tests inject `FakeLandscapeSource`.

## Typed slices

`ConfigSchema.validate` returns an immutable `DieneConfig`:

- `slice(block)` — the typed value from the block's own decoder;
- `hasSlice(block)` / `optionalSlice(block)` — for a `required: false` block;
- `rawSlice(key)` — an untyped view of a block nobody has a decoder for yet;
- `raw` — the whole final tree, deeply unmodifiable;
- `stableProjection()` — a deterministic, sorted-key projection for hashing or
  diffing, delegated to `stableConfig`.

## C0 §3 conformance

`package:diene_config/c0_config.dart` exports `c0ConfigContract`, the pinned
identity of the frozen release this package binds (`c0-fixtures-r2`). The
vectors themselves are not restated in Dart: `tool/gen_c0_projection.dart`
projects them from `contracts/c0/cases/config.json` into
`test/fixtures/c0/config.json` with a SHA-256 ledger, and
`test/conformance/c0_config_test.dart` drives the **real** loader from that
projection. Changing the normative release either flows through or reddens the
`--check` gate; it cannot be diverged from by editing an assertion.

This package binds all **five** §3 vectors. `diene_core_utils` projects only
four: `finalLayerValidation` is the one it leaves to its consumer, because
validating the merged layer is this package's responsibility.

## TestHelper

Import `package:diene_config/test_helper.dart` for `FakeConfigSource`,
`FailingConfigSource`, `FakeLandscapeSource`, `ConfigStubBuilder`,
`FakeConfigHarness`, and the `expectOkConfig` / `expectErrConfig` /
`assertConfigProblem` / `assertConfigSlice` assertions. It imports no test
framework or mocking package — it ships inside the published archive, and a
`package:test` import there would force that dependency on every consumer.
Failures throw `ConfigAssertionFailure` (a `StateError`), so any runner reports
them.

`ConfigStubBuilder` builds through the **real** `ConfigSchema.validate`, so a
stub cannot be shaped like a configuration the loader would reject.
`FakeConfigHarness` drives the **real** `ConfigLoader`, so it cannot drift from
the production ladder. The meta suite runs the same layer matrix through the
fakes and through real YAML and compares both channels.

## Migrating from an in-app `config/app_config.dart`

An app carrying its own `lib/config/app_config.dart` can swap the import
instead of every call site:

```dart
// was: import 'config/app_config.dart';
import 'package:diene_config/config/app_config.dart';
```

That entrypoint re-exports the whole surface and adds `AppConfig`, a one-shot
process-wide holder (`install`, `instance`, `maybeInstance`, `loadAndInstall`,
`reset`). It is a **migration aid**, not the recommended surface: reading
`AppConfig.instance` before `install` throws rather than handing back a silent
default, and a second `install` without `force` throws rather than letting two
parts of the app disagree. New code imports `package:diene_config/diene_config.dart`
and threads `DieneConfig` through constructors. A migrated app is finished when
nothing imports `config/app_config.dart`.

## Parity with lib/bun/config

Kept in parity:

- full base → sparse landscape overlay → development hook → injected values last;
- configurable prefix, `__` nesting, case- and separator-insensitive matching;
- indexed environment lists, no JSON/comma decoding, blank-is-unset;
- service-composed root schemas assembled from engine-owned blocks;
- final-layer-only validation, immutable typed slices;
- dependency-light fake layers with real-versus-fake meta coverage.

Deliberate Dart deltas:

- **Defines are enumerated, not enumerated-over.** Dart has no runtime
  environment enumeration, so the application lists its `String.fromEnvironment`
  keys explicitly; the Bun sibling reads `process.env` wholesale.
- **No server or runtime-secret dimension.** This family is frontend-only, so
  there is no `/build-time` subpath, no standard-config member, and no OTel
  config or exporter block. Telemetry rides Faro.
- **YAML input is callback-based**, so one source type serves Flutter assets,
  `dart:io`, and in-memory documents without the package depending on any of
  them.
- **Schemas are typed decoder callbacks**, not Zod schemas. A decoder throws to
  reject its input and the schema folds that into the aggregate problem, so an
  engine describing its own settings needs no dependency on `diene_result`.
- **The landscape accessor lives here.** Dart has no frontend-utils family
  member to host it.
- **Merge primitives are consumed, not owned.** Both siblings delegate to their
  core-utils; the Dart split additionally moves environment-key parsing there,
  so this package owns YAML reading and orchestration only.
