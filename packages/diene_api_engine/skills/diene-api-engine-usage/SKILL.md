---
name: diene-api-engine-usage
description: Use when calling backends from a diene Dart/Flutter app — register LPSM backends, make Result-typed calls, handle Problems, and fake backends in tests with diene_api_engine.
---

# diene_api_engine usage

`diene_api_engine` is the client-side backend layer. Every call returns
`Result<T, Problem>`; nothing throws.

## Register (LPSM client tree)

- One backend = one `LpsmCoordinate` (`landscape.platform.service.module`) +
  one base-URL **hostname** from config values (never a literal) + an optional
  per-resource auth binding.
- Build the engine from the engine-owned config block:
  `ApiEngine.fromConfig(config, auth: retriever, store: FileRescueStore(dir))`.
- Resolve a backend with `engine.backend(coordinate)`. Duplicate registrations
  are a typed `Err`, not a throw.

## Multi-backend

- ONE app registers MANY backends. Tokens resolve **per backend** through the
  `IAuth` seam (`tokenFor(coordinate, resource:)`) — never a shared/singleton
  token. Auth-engine's onboarding machinery keys off the same registrations.

## Call + handle Problems

```dart
final r = await backend.call(method: HttpMethod.get, path: '/user/me', decode: X.fromJson);
r.match(ok: use, err: showProblem);
```

- Classification (`toResult`): 2xx JSON → `Ok`; problem body → that `Problem`;
  non-problem JSON error → unexpected-response Problem; network/non-JSON/
  status-only → transport-failure Problem.

## Resilience (don't hand-roll it)

- Retry-once on opaque network error is automatic; received statuses (incl.
  5xx) are never retried.
- The dormant rescue router wakes only on a hard connect-failure (Flutter/
  browser contexts). It rescues **addresses only, same landscape**, behind a
  baked suffix allowlist + monotonic doc versions + always-baked issuer. Do not
  add your own physical-URL list, circuit breaker, or failover ladder.

## TestHelper

`import 'package:diene_api_engine/test_helper.dart';` (dependency-light):

- `FakeHttpTransport.byHost({...})` / `.sequence([...])` — scripted transports.
- `FakeAuth({coordKey: token})` — per-backend tokens; `.queried` proves no
  cross-backend bleed.
- `FakeRescueStore`, `noSleep`, `noJitter` — deterministic rescue tests.
- `expectOk` / `expectErr` / `expectProblemType` — plain-throw assertions.
- `okJson` / `problemResponse` / `nonProblemJson` / `nonJsonResponse` /
  `networkFailure` — reconciliation-matrix builders.
