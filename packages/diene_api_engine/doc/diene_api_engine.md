# diene_api_engine

The typed OA3 backend-client engine for the Diene Dart family. It wraps generated
OpenAPI SDK calls into `Result<T, Problem>`, registers N backends on the LPSM
client tree with per-resource auth through the `diene_auth_engine` `IAuth` seam,
retries once on a hard network failure, and ships a **dormant** disk-cached rescue
router for same-landscape address failover. Client-side only; the Dart family is
frontend-only and carries no OTel library — telemetry rides Faro.

## Public surface

Import only the barrel:

```dart
import 'package:diene_api_engine/diene_api_engine.dart';
```

`Result`, `Ok`, `Err` and `Problem` are owned by `diene_result` / `diene_problems`,
and `IAuth`, `ResourceKey`, `ResourceToken` by `diene_auth_engine`. They are
re-exported for convenience and never redefined here.

- **Engine** — `ApiEngine.fromConfig(config, {auth, transport, store,
rescueOverride})`, `ApiEngine.backend(coordinate)`, `Backend.call<T>(...)`,
  `Backend.sdk<S>(...)`, `BackendClientAdapter`.
- **Client tree** — `ClientTree.register/resolve/contains/backends`, keyed by
  `LpsmCoordinate` (`landscape.platform.service.module`).
- **Config block** — `ApiEngineConfig`, `BackendConfig`, `RescueConfig`,
  `LpsmCoordinate`, and the engine-owned schema `ApiEngineConfig.schema`.
- **Bridge** — `toResult`, `isProblemJson`, `tryDecodeObject`, `BridgeProblems`.
- **Transport** — `HttpTransport`, `IoHttpTransport`, `RetryOnceTransport`,
  `HttpRequest`, `HttpResponse`, `TransportOutcome` (`Received` / `NetworkFailure`),
  `HttpMethod`.
- **Rescue** — `RescueRouter`, `RescueOutcome` (`Rescued` / `RescueUnavailable`),
  `RescueStore` (`InMemoryRescueStore`, `FileRescueStore`), `DocA`, `DocC`.
- **OA3** — `ResultSdk`.

## Engine-owned config block

This engine **owns and exports its own config-block schema**
(`$id: urn:diene:config-block:api-engine`). `diene_config` merges and validates
the service-composed root schema assembled from engine-owned blocks; it never owns
another lib's schema. The block carries `backends` and `rescue`, and deliberately
carries **no `otel` key** — the Dart family is exempt from the C0 otel block.

## Resilience: retry-once, then a dormant router

Each registered backend is **one hostname**. The hot path is
**retry-once-on-network-error** only — there is no always-on physical-URL list, no
circuit breaker and no failover ladder.

On a HARD connect failure that survives that single retry, and only when the
per-context flag is enabled, the request hands off to the **rescue router**:

- **Doc A** supplies `catalogHosts[]`, fetched once tripped and cached to disk.
- **Doc C** supplies the ordered candidate addresses, keyed
  `landscape.platform.service.module`.
- Candidates are scanned with **jitter that counts toward a global budget**; a
  hanging probe fails closed so it cannot exceed that budget.
- A healthy candidate is **pinned until the primary heals**.
- **Last-known-good is kept forever** and is the final fallback.
- **Monotonic versions**: an older document is rejected, and a rollback is
  rejected explicitly.
- The **baked endpoint-suffix allowlist is enforced on every doc-sourced URL at
  use time** — on Doc A's host list, the Doc C fetch URL, every Doc C candidate,
  the pin when read back, and last-known-good before use.
- The **auth issuer is always baked** build-time config and is never doc-sourced.
- The router rescues **addresses only**, and **only within the same landscape**.
  That is guaranteed _by construction_ rather than by a runtime check: candidates
  are looked up by a key that contains the landscape, so an address from another
  landscape is not reachable by the lookup.

## Parity with the `lib/bun` sibling — deliberate deltas

The dart family has **no `frontend-utils` lib**, so the discovery/rescue machinery
that bun splits out lives HERE. This is the documented delta the family goal
requires; the behaviour is the twin of bun's, only the placement differs.

| Concern                    | `lib/bun`                                      | `lib/dart`                                                                |
| -------------------------- | ---------------------------------------------- | ------------------------------------------------------------------------- |
| Doc A — catalog-hosts seed | `frontend-utils` `src/lib/discovery/doc-a.ts`  | **this package**, `DocA`                                                  |
| Doc C — ordered candidates | `frontend-utils` `src/lib/discovery/doc-c.ts`  | **this package**, `DocC`                                                  |
| Rescue router              | `frontend-utils` `src/lib/discovery/rescue.ts` | **this package**, `RescueRouter`                                          |
| Doc B — landscape selector | `frontend-utils` `src/lib/discovery/doc-b.ts`  | **`diene_auth_engine`** (`landscape_selector`), used once at sign-up only |
| Client tree                | `api-engine` `src/client-tree.ts`              | this package, `ClientTree`                                                |
| HTTP client                | `api-engine` `src/http-client.ts`              | this package, `transport.dart`                                            |

Other deltas:

- **On-disk cache** is `dart:io` (`FileRescueStore`) rather than a browser storage
  adapter.
- **Flutter SDK dependency.** Unlike the pure-Dart siblings, this package requires
  Flutter transitively through `diene_auth_engine`, so its gates run
  `flutter pub` / `flutter test` and pana is given an explicit `--flutter-sdk`.
- **No SSR surface**, matching `diene_result`: SSR is a TS/Next-only concern.

## TestHelper and meta testing

```dart
import 'package:diene_api_engine/test_helper.dart';
```

Dependency-light by rule: fakes, builders and plain-throw assertions only, with
**no test-framework dependency**, so it adds nothing to a consumer's production
graph. `scripts/validate/dart-package.sh` asserts that boundary.

- **Assertions** — `expectOk`, `expectErr`, `expectProblemType`, `check`.
- **Builders** — `problemFixture`, `okJson`, `problemResponse`, `nonProblemJson`,
  `nonJsonResponse`, `networkFailure`.
- **Fakes** — `FakeHttpTransport`, `HangingTransport`, `FakeAuth`,
  `FakeRescueStore`, `FakeClock`, `noSleep`, `noJitter`.

The meta tier's subject is the TestHelper itself; its ledger is scoped to the
helper subtree plus its barrel, and helper code is excluded from the unit ledger.

## C0 conformance

`test/fixtures/c0/problem_envelope.json` is **projected** from the frozen neutral
release `c0-fixtures-r2`, never hand-edited. It is regenerated by
`scripts/validate/gen-c0-projection.sh` and byte-checked by
`scripts/validate/c0-release.sh`, which also authenticates the whole
`contracts/c0/` tree against its manifest and pinned digest.
