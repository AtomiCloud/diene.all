# diene_problems — Dart RFC 9457 problem-details library

<!-- ### dart-lib-doc -->
<!-- #### source: lib/dart/problems -->

`diene_problems` is the Dart-family port of the L-bun `problems` contract
(C0 §2 problem schema, §14 problem-catalog schema). It owns: the RFC 9457
envelope with the `data` extension, the single-source type-URI builder, a typed
registry, an error→Problem transformer, `LocalError` wrapping, and per-endpoint
catalog export including the `recoverable` flag.

## Surface

| Member                                                | Purpose                                                                                                                 |
| ----------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `Problem`                                             | RFC 9457 envelope (`type`/`title`/`status`/`detail`/`instance`) + `data` + `recoverable`; `toJson`/`fromJson`.          |
| `problemTypeUri` / `ErrorPortal`                      | The ONE type-URI builder for `{scheme}://{host}/docs/{landscape}/{platform}/{service}/{module}/{version}/{id}` (C0 §2). |
| `ProblemType` / `ProblemRegistry` / `GenericProblems` | Versioned type declarations; registry resolves each type's URI through the builder; ships the portable generic set.     |
| `fromObject` / `TransformOptions`                     | Folds an arbitrary value into a typed `Problem` (HTTP bridge lives in `diene_api_engine`).                              |
| `LocalError` / `ErrorSink`                            | Wraps unexpected client exceptions into a `LocalError` Problem (message + stacktrace in `data`).                        |
| `CatalogEntry` / `CatalogEndpoint` / `ProblemCatalog` | Per-endpoint catalog EXPORT (C0 §14); emits `Problem` CR content consumed by the edge error portal.                     |

## The single-source type URI

The type URI is built in exactly ONE place — `problemTypeUri`. Every problem
(catalog entries, runtime envelopes, local errors) resolves its `type` through
it, so a version bump mints a NEW problem type (`{version}` is part of the
contract identity). The LPSM segments arrive via an `ErrorPortal` config block,
never hardcoded (R4).

```text
https://docs.raichu.cluster.atomi.cloud/docs/raichu/dotnet/user/api/v1/entity-not-found
        └────── host ──────┘      └ landscape └ platform/service/module └ ver └ id
```

## Catalog export (C0 §14)

Each service publishes a `Problem` catalog CR (per service × landscape). This
library is the PRODUCER side: `ProblemCatalog.toCrdContent()` renders the
declared set as the CR's `problems[]` list — `{ id, type, title, status,
recoverable, data, endpoints[] }`. There is NO runtime error-info HTTP surface;
runtime `/error-info` endpoints are replaced by this catalog, not wrapped.
Frontends classify recoverable-vs-fatal from the edge-published catalog and
never call Primordial, including during error storms.

```dart
final catalog = ProblemCatalog(portal: portal)
  ..addType(GenericProblems.validationError, endpoints: [
    CatalogEndpoint(method: 'POST', path: '/user'),
  ])
  ..addGenerics();

final List<Map<String, Object?>> crd = catalog.toCrdContent();
```

## LocalError

Dart frontends wrap unexpected exceptions into a `LocalError` Problem (message +
stacktrace in `data`), rendered by a Problem visualizer shipped in
`flutter-base`. The type URI still flows through `problemTypeUri`:

```dart
final problem = await LocalError(sink, portal: portal).wrap(error, StackTrace.current);
```

## TestHelper (dependency-light)

`package:diene_problems/test_helper.dart` is a sub-library of framework-free
helpers (`expectProblem`, `aProblem`, `anErrorPortal`, `aCatalogEntry`) that
throw plain `AssertionError`s on mismatch. It adds nothing to a consumer's prod
dependency graph. See `skills/diene-problems-usage/SKILL.md`.

## Parity deltas vs `lib/bun/problems`

| Area                 | Bun (`@atomicloud/diene.problems`)          | Dart (`diene_problems`)                               | Delta reason                                                                                                              |
| -------------------- | ------------------------------------------- | ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| `data` schema        | `zod` schema                                | JSON-Schema-shaped `Map<String, Object?>`             | No zod equivalent in the Dart dependency graph; the schema IS JSON, authored as a map. Dependency-light.                  |
| Transformer          | `fromError` + `fromHttpError(response)`     | `fromObject` only                                     | The HTTP→Problem bridge (`fromHttpError`) lives in `diene_api_engine` for Dart, same split as bun (bridge in api-engine). |
| LocalError           | Lives in `frontend-utils`                   | Lives HERE (`diene_problems`)                         | Dart has no `frontend-utils` lib; the Dart family folds LocalError into the problems lib (goal row decision).             |
| TestHelper packaging | `diene.problems/test-helper` subpath export | `package:diene_problems/test_helper.dart` sub-library | Dart auto-discovers top-level `lib/*.dart` as importable libraries; no manifest subpath needed.                           |
| Deadcode gate        | `knip` (strict + production)                | `dart analyze` whole-package + `dart analyze lib`     | Dart has no knip equivalent; analyzer scoping is the two-pass analogue (R12 — no exclusion lists).                        |
| Versioning           | ESM+CJS+types; npm                          | Pure Dart package; pub.dev                            | Dart is frontend-only, pub.dev distribution.                                                                              |
| SSR surface          | n/a (bun has none either)                   | none                                                  | SSR is TS/nextjs-only; not ported.                                                                                        |

## Stacking on `diene_core_utils` and `diene_result` (later)

The internal DAG is `result → interfaces → core-utils → {config, problems,
auth-engine}`. Those siblings ship in parallel lanes and are not imported here
(optimistic concurrency — no uncommitted cross-lane imports). The intended later
wiring, documented for the conductor's stacking pass:

- **`diene_config`**: the `ErrorPortal` LPSM segments are sourced from the
  service-composed config's `app:` block (build-time `--dart-define` for
  flutter). Once `diene_config` lands, consumers build the portal from a typed
  config slice instead of hand-constructing it. No change to this lib's API —
  `ErrorPortal` is already a plain value object.
- **`diene_result`**: the `Failure<T>` variant already carries a `Problem`. Once
  `diene_result` lands, `fromObject`/`LocalError` compose naturally with
  `Result<T, Problem>` (e.g. `Failure<T>(await LocalError(sink).wrap(e, st))`).
  No change to this lib's API — `Problem` is already the shared error type.

Until then, `diene_problems` is fully usable standalone (zero runtime deps): the
envelope, builder, registry, transformer, LocalError, and catalog export all
work without `result`/`core-utils`.

## Telemetry

Dart is frontend-only (C0 §4 exemption): no otel exporter. The `ErrorSink` seam
stays owned here with a no-op default; at runtime flutter/flutter-base forwards
captures to Faro via the frontend machinery, never an otel exporter.
