# Dart configuration standard

`diene_config` owns configuration mechanics: layer loading, deep merge,
override decoding, one final validation pass, and typed slice access. It does
not own auth, API, telemetry, or service schemas. Each engine exports its own
`ConfigBlock<T>` beside the code that consumes it; the application composes
those blocks with its own keys into `ConfigSchema`.

## Layer order

1. Full base YAML defines every overrideable path and default.
2. One sparse flavor or landscape YAML overlays the base.
3. An optional development source provides a controlled local hook.
4. Enumerated `--dart-define` values apply last.
5. The service-composed schema validates the final tree once. No intermediate
   layer is validated or exposed.

Configuration is immutable after loading. There is no watch/reload API in v1.
Flutter callers normally provide `rootBundle.loadString`; pure Dart callers can
provide `File(path).readAsString`. The package itself stays independent of both
Flutter and `dart:io`.

## Defines and indexed lists

The prefix is required and application-owned; `ATOMI_` is only an example.
`__` separates nesting. Matching ignores case, hyphens, and underscores, so
snake, kebab, camel, and Pascal forms resolve to the key authored in base YAML.
Unknown paths fail rather than silently creating typo keys.

Lists use contiguous indexed keys:

```text
ATOMI_AUTH__SCOPES__0=openid
ATOMI_AUTH__SCOPES__1=offline_access
```

The first indexed key replaces the YAML list. JSON and comma encodings are not
accepted. Blank values are unset. Scalars coerce only to booleans, integers,
or doubles; everything else remains a string for the owning block decoder to
validate.

## Landscape accessor

`landscape()` reads the build-time `DIENE_LANDSCAPE` define. A mobile store
track is the landscape. The accessor performs no hostname sniffing, runtime
environment lookup, or remote detection. Landscape is identity, never a
secret. Tests inject `FakeLandscapeSource`.

## TestHelper

Import `package:diene_config/test_helper.dart` for `FakeConfigSource`,
`FakeConfigHarness`, `FakeLandscapeSource`, and `ConfigStubBuilder`. The helper
has no test-framework or mocking-package dependency. Stubs pass through the
production composed schema, and the meta suite runs the same behavior against
real YAML and fake sources.

## Parity with lib/bun/config

Kept in parity:

- full base → sparse landscape → injected values last;
- configurable prefix, `__` nesting, case/style-insensitive key matching;
- indexed environment lists and blank-is-unset behavior;
- service-composed root schemas made from engine-owned blocks;
- final-layer-only validation, immutable typed slices, and a dev override;
- dependency-light fake layers with real-versus-fake meta coverage.

Deliberate Dart deltas:

- Dart/Flutter has no runtime environment enumeration, so applications
  explicitly enumerate `String.fromEnvironment` values;
- this frontend-only family has no server/runtime-secret dimension,
  `/build-time` subpath, standard-config member, or OTel config/exporter;
- YAML input is callback-based to remain portable across Flutter assets and
  pure Dart IO;
- schemas are typed decoder blocks rather than Zod schemas;
- the landscape accessor is co-located here because Dart has no
  frontend-utils family member.

Later conductor-owned stacking adds the published `diene_core_utils`
dependency for the canonical deep-merge/coercion primitives without changing
this public contract, then stacks engine packages whose blocks consumers
compose here.
