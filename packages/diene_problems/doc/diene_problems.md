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

The builder validates every segment at the boundary, matching the published
`@atomicloud/diene.problems` builder pattern-for-pattern so a wire id minted in
one language family is accepted by all four:

| Segment                                   | Pattern                        | Constant                |
| ----------------------------------------- | ------------------------------ | ----------------------- |
| `landscape`/`platform`/`service`/`module` | `^[A-Za-z0-9][A-Za-z0-9._-]*$` | `problemSegmentPattern` |
| `version`                                 | `^v[0-9]+$`                    | `problemVersionPattern` |
| `id` (the WIRE id)                        | `^[a-z][a-z0-9_]*$`            | `problemWireIdPattern`  |

`host` is additionally validated as a canonical bare authority (`host` or
`host:port`), so a doc-sourced portal carrying a path, query, fragment,
credentials, or whitespace is refused rather than silently producing a malformed
URI.

### Wire ids are snake_case (R-E14)

R-E14 amended C0 §7: the **definition/factory** name stays PascalCase
(`AppHandoffExpired`) while the **wire** id is `app_handoff_expired`. Every
shipped id follows it — `validation_error`, `entity_not_found`, `invalid_json`,
`local_error` — and the builder rejects anything else.

The frozen C0 release this package projects (`c0-fixtures-r2`) predates the
amendment and still samples KEBAB ids in its `problem.json` vectors. Those bytes
are authoritative for the envelope member vocabulary and the type-URI TEMPLATE
and are **never rewritten here** — a corrected round is owed at the release owner
(R-E8a: fixed once, inherited by merge). Sample ids are instead projected through
one narrow documented normalization, `r14WireId` (`-` → `_`), and
`test/conformance/c0_wire_id_variance_test.dart` pins the pair so neither side
can drift silently.

```text
https://docs.raichu.cluster.atomi.cloud/docs/raichu/dotnet/user/api/v1/entity_not_found
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

| Area                 | Bun (`@atomicloud/diene.problems`)                       | Dart (`diene_problems`)                                                                               | Delta reason                                                                                                                                                                                                                                                                    |
| -------------------- | -------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `data` schema        | `zod` schema                                             | JSON-Schema-shaped `Map<String, Object?>`                                                             | No zod equivalent in the Dart dependency graph; the schema IS JSON, authored as a map. Dependency-light.                                                                                                                                                                        |
| Transformer          | `fromError` + `fromHttpError(response)`                  | `fromObject` only                                                                                     | The HTTP→Problem bridge (`fromHttpError`) lives in `diene_api_engine` for Dart, same split as bun (bridge in api-engine).                                                                                                                                                       |
| LocalError           | Lives in `frontend-utils`                                | Lives HERE (`diene_problems`)                                                                         | Dart has no `frontend-utils` lib; the Dart family folds LocalError into the problems lib (goal row decision).                                                                                                                                                                   |
| TestHelper packaging | `diene.problems/test-helper` subpath export              | `package:diene_problems/test_helper.dart` sub-library                                                 | Dart auto-discovers top-level `lib/*.dart` as importable libraries; no manifest subpath needed.                                                                                                                                                                                 |
| Deadcode gate        | `knip` (strict + production)                             | `dart_code_linter:metrics check-unused-code`/`check-unused-files`, whole-package then production-only | Dart has no knip equivalent; the two dart_code_linter passes are the analogue (R12 — no exclusion lists). The production pass needs `tool/deadcode_entrypoints.dart` as its root, because the analyzer would otherwise report the shipped `test_helper.dart` members as unused. |
| Versioning           | ESM+CJS+types; npm                                       | Pure Dart package; pub.dev                                                                            | Dart is frontend-only, pub.dev distribution.                                                                                                                                                                                                                                    |
| SSR surface          | n/a (bun has none either)                                | none                                                                                                  | SSR is TS/nextjs-only; not ported.                                                                                                                                                                                                                                              |
| Wire-id casing       | `^[a-z][a-z0-9_]*$` enforced in the builder              | identical pattern, identical enforcement point                                                        | **No delta** — R-E14 is implemented the same way in both families. Recorded because the pattern is a cross-family contract, not a local style choice.                                                                                                                           |
| Type-URI validation  | segment/version/host patterns + `new URL()` canonicality | same three patterns + `Uri` canonicality check                                                        | **No delta** in accepted/rejected inputs; the implementations differ only in using Dart's `Uri` instead of WHATWG `URL`.                                                                                                                                                        |
| Package version      | `1.0.0`                                                  | `0.1.1`                                                                                               | Independent release cadence per lib (family rule). Dart is pre-1.0 while its consumers pin `^0.1.0`; `0.1.0` was a rejected-content bootstrap and is retracted (R-E24a), never reused.                                                                                          |

## Position in the Dart family DAG

`diene_problems` is the **root** of the Dart family, not a leaf. Dart's package
design is deliberately the REVERSE of bun's (RB-315, and the R-E32 goal
amendment): this package owns the sole public RFC 9457 `Problem` and has **zero
dependencies**, while `diene_result` and `diene_interfaces` consume it as a
hosted pub.dev dependency (`diene_problems: ^0.1.0`).

That ownership is one-way and must stay so — importing `diene_result` here would
create exactly the cycle the ruling forbids. The dependency direction is why the
`data` payload is a plain JSON map and the catalog schema is a
JSON-Schema-shaped `Map` rather than a `Result`-based or schema-library type.

## Stacking on `diene_config` and `diene_result` (later)

Those siblings are downstream or parallel and are not imported here. The
intended later wiring, documented for the conductor's stacking pass:

- **`diene_config`**: the `ErrorPortal` LPSM segments are sourced from the
  service-composed config's `app:` block (build-time `--dart-define` for
  flutter). Once `diene_config` lands, consumers build the portal from a typed
  config slice instead of hand-constructing it. No change to this lib's API —
  `ErrorPortal` is already a plain value object.
- **`diene_result`**: its `Err` variant already carries a `Problem` — it depends
  on THIS package's `Problem`, so composition happens on the CONSUMER side
  (`Err<T>(await LocalError(sink).wrap(e, st))`), never by importing
  `diene_result` here. No change to this lib's API is needed or permitted.

`diene_problems` is fully usable standalone by design (zero runtime deps): the
envelope, builder, registry, transformer, LocalError, and catalog export all work
with nothing else installed.

## Telemetry

Dart is frontend-only (C0 §4 exemption): no otel exporter. The `ErrorSink` seam
stays owned here with a no-op default; at runtime flutter/flutter-base forwards
captures to Faro via the frontend machinery, never an otel exporter.
