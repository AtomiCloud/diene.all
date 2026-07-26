---
name: diene-problems-usage
description: Use when building, registering, transforming, wrapping, or catalog-exporting RFC 9457 Problem envelopes in Dart (diene_problems), or asserting them in tests.
---

# diene_problems usage

`diene_problems` is the Dart-family RFC 9457 problem-details library. Read
[the library doc](../../doc/diene_problems.md) for the full surface and
parity deltas; this skill is the thin trigger for the two things consumers do
most: catalog usage and TestHelper matching.

## Build a type URI (the ONE place)

Never hand-format the template. Always go through `problemTypeUri` (or the
registry/catalog, which use it internally):

```dart
final portal = ErrorPortal(
  scheme: 'https', host: 'docs.raichu.cluster.atomi.cloud',
  landscape: 'raichu', platform: 'dotnet', service: 'user', module: 'api',
);
// https://docs.raichu.cluster.atomi.cloud/docs/raichu/dotnet/user/api/v1/entity_not_found
final uri = problemTypeUri(portal: portal, version: 'v1', id: 'entity_not_found');
```

## Register + consume the generic catalog

```dart
final registry = ProblemRegistry(portal)..register(GenericProblems.entityNotFound);
registry.typeUriFor(GenericProblems.entityNotFound); // single-source URI

final catalog = ProblemCatalog(portal: portal)
  ..addType(GenericProblems.validationError,
            endpoints: [CatalogEndpoint(method: 'POST', path: '/user')])
  ..addGenerics();
final crd = catalog.toCrdContent(); // ship as the Problem CR content (C0 §14)
```

Generic baseline set (versioned URIs, shared namespace; domain problems stay in
consumer services): `validationError`, `entityNotFound`, `conflict`,
`unauthenticated`, `unauthorized`, `invalidJson`.

## Wrap unexpected exceptions

```dart
final problem = await LocalError(sink, portal: portal).wrap(error, StackTrace.current);
// problem.data == { message, stackTrace }; type URI built via problemTypeUri
```

## Fold an unknown value into a Problem

```dart
final p = fromObject(someError, options: TransformOptions(registry: registry, portal: portal));
// known id on a Map → registry type; otherwise uncatalogued fallback (C0 §14)
```

## Assert Problems in tests (TestHelper)

`package:diene_problems/test_helper.dart` is framework-free — it throws a plain
`ProblemMatcherError` (an `AssertionError`) on mismatch, so it works from
`package:test`, `flutter_test`, or any runner without a test-framework dep.

```dart
import 'package:diene_problems/test_helper.dart';

expectProblem(result, type: uri, status: 404, recoverable: false,
              data: {'resource': 'user'});

final fixture = aProblem(id: 'entity_not_found', status: 404);
final entry = aCatalogEntry(id: 'validation_error', status: 400, recoverable: true);
```

Only the fields you pass are checked. The meta tier (`pls test:meta`) proves
every matcher fails on a known-bad case and passes on a known-good one.
