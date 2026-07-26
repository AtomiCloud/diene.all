# diene_problems patterns

Deeper guidance behind [SKILL.md](SKILL.md). Read the
[library doc](../../doc/diene_problems.md) for the full surface and the parity
deltas vs the bun sibling.

## Wire ids are snake_case, and the builder enforces it

The **wire** id is `entity_not_found`. The **definition/factory** name stays
PascalCase (`EntityNotFound`) — that split is R-E14's whole point, and C0 §7 was
amended to say so. `problemTypeUri` rejects anything that is not
`^[a-z][a-z0-9_]*$`, the same pattern the published
`@atomicloud/diene.problems` builder enforces, so an id minted in Dart resolves
identically in TypeScript, C#, and Go.

```dart
problemTypeUri(portal: portal, version: 'v1', id: 'entity_not_found'); // ok
problemTypeUri(portal: portal, version: 'v1', id: 'entity-not-found'); // throws
problemTypeUri(portal: portal, version: 'v1', id: 'EntityNotFound');   // throws
```

If you are porting vectors from an older document or fixture that still uses
kebab, normalize with `r14WireId` rather than editing the source:

```dart
final String wireId = r14WireId('entity-not-found'); // entity_not_found
```

`version` must be `v<n>` and `host` must be a bare authority (`host` or
`host:port`) — a portal carrying a path, query, fragment, credentials, or
whitespace is rejected at the boundary instead of producing a malformed URI.
That matters because in production the portal comes from config, and a
misconfigured landscape should fail loudly rather than mint a second identity
for the same problem.

## A version bump mints a NEW problem type

`{version}` is part of the contract identity, so `v1` → `v2` is a _new_ problem,
not an edited one. Register both while consumers migrate; never mutate a live
type's meaning in place.

```dart
registry
  ..register(const ProblemType(id: 'payment_declined', title: 'Declined', version: 'v1'))
  ..register(const ProblemType(id: 'payment_declined', title: 'Declined', version: 'v2'));
```

Ids are unique per registry, so the pair above needs two registries (or two
distinct ids) — which is the intended friction: it forces you to decide whether
you are versioning a contract or naming a different failure.

## Registry vs catalog — two different jobs

|         | `ProblemRegistry`                               | `ProblemCatalog`                     |
| ------- | ----------------------------------------------- | ------------------------------------ |
| Holds   | `ProblemType` declarations                      | `CatalogEntry` rows with `endpoints` |
| Used at | runtime, to resolve a type URI or fold an error | build/publish time, to EXPORT the CR |
| Emits   | URIs via `typeUriFor`                           | `toCrdContent()`                     |

Build the catalog **from** the registry with `addType`, never by hand-writing a
`CatalogEntry` with a literal `typeUri` — that reintroduces the second template
this library exists to eliminate. `aCatalogEntry` in the TestHelper is the one
sanctioned shortcut, and it still mints its URI through the builder.

```dart
final catalog = ProblemCatalog(portal: portal);
for (final ProblemType type in registry.entries) {
  catalog.addType(type, endpoints: endpointsFor(type));
}
```

## `recoverable` is the frontend's contract, not a hint

`recoverable` travels on both the envelope and the catalog entry, and the
flutter Problem visualizer classifies retry-vs-fatal from the **edge-published
catalog** — never by calling Primordial, and never during an error storm. So set
it deliberately per type: `true` means "offering a retry button is correct".

There is no runtime error-info endpoint to fall back on; the catalog _replaces_
that surface rather than wrapping it.

## `fromObject` never throws — that is the point

It always returns a `Problem`, so it is safe in a `catch` block or at any
boundary where you cannot reason about the value:

- already a `Problem` → returned unchanged;
- a `Map` carrying a `problemId` a registry knows → that type's URI, title,
  status, and `recoverable`, with `data` preserved;
- anything else → the uncatalogued problem (`uncataloguedProblemId`) at
  `defaultStatus`, with `detail` set from `toString()`.

Uncatalogued means 5xx by C0 §14's catalog-loop rule: an unknown problem must
never look like a client error the caller could fix.

```dart
try {
  await doWork();
} on Object catch (error) {
  final Problem problem = fromObject(
    error,
    options: TransformOptions(portal: portal, registry: registry),
  );
  return Err<T>(problem); // on the consumer side; this package never imports diene_result
}
```

Only structured `Map`s are inspected for `problemId` — dynamic getters are
deliberately not probed (`avoid_dynamic_calls`), so give the transformer a map
when you want registry resolution.

## `ErrorSink` is a seam, not a logger

`LocalError.wrap` builds the Problem, hands it to the sink, and returns it. In
production the sink forwards to Faro through the frontend machinery (Dart is
frontend-only; there is no otel exporter here). `NoopErrorSink` ships for the
cases where you only want the envelope.

```dart
final class FaroErrorSink implements ErrorSink {
  @override
  Future<void> capture(Problem problem) async => faro.pushError(problem.toJson());
}
```

Pass your real build-time portal so local-error type URIs land under the real
docs host; `ErrorPortal.localError` is a fallback that keeps the builder usable
in isolation and in tests, not a production default.

## This package is the family root — the dependency only goes one way

`diene_problems` owns the sole public `Problem` and has **zero runtime
dependencies**. `diene_result` and `diene_interfaces` depend on it. Importing
either of them here would create the cycle RB-315 forbids, which is why the
`data` payload is a plain JSON map and the catalog schema is a
JSON-Schema-shaped `Map` rather than a schema-library or `Result`-based type.

Compose on the **consumer** side instead: `Result<T, Problem>` works because
`diene_result` already depends on this `Problem`.

## The C0 projection is generated — never hand-edit it

`lib/src/c0_problem_contract.g.dart` and `test/fixtures/c0/*.json` are projected
from the frozen, digest-authenticated release under `contracts/c0/`.

```console
dart run tool/gen_c0_projection.dart          # regenerate
dart run tool/gen_c0_projection.dart --check  # verify committed bytes
./scripts/validate/c0-release.sh              # full release authentication
```

Editing a projected byte fails `--check`, and editing the release fails its own
digest. `c0ProblemContract.provenance` exposes the release id and digest at
runtime, so a consumer can assert which authenticated contract a build carries.

## Testing patterns

`expectProblem` checks only the fields you pass, and names the first mismatched
field in its message — so assert the fields the behaviour under test actually
determines, not the whole envelope:

```dart
expectProblem(problem, status: 404, recoverable: false);          // focused
expectProblem(problem, data: {'resource': 'user', 'id': 42});     // deep, order-insensitive
```

`data` comparison recurses through nested maps and lists, so a validation
payload's `fields` array is compared element by element rather than by length.

Prefer the builders over literals so tests never hand-format a URI:

```dart
final Problem p = aProblem(id: 'entity_not_found', status: 404);
final ErrorPortal portal = anErrorPortal(landscape: 'pichu');
final CatalogEntry e = aCatalogEntry(id: 'validation_error', status: 400, recoverable: true);
```

The helper is dependency-light on purpose: it throws plain `AssertionError`s and
adds no test-framework package to your production dependency graph, so importing
`test_helper.dart` from app code costs nothing at runtime.
