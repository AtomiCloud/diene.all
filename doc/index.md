# diene_e2e — version-train and consumer test-harness

`diene_e2e` is the single package a consumer of the L-dart family depends on. It
plays two roles, mirroring `lib/bun/e2e`:

1. **Version train** — one dependency pins a coherent set of the family
   libraries, so a consumer upgrades one version instead of reconciling seven.
2. **Consumer test-harness** — bundles every family member's `test_helper.dart`
   that exists, plus this package's own harness glue.

## Import roots

- `package:diene_e2e/diene_e2e.dart` — the runtime version-train re-exports
  (integration-held; see below) and the pure-value C0 §7 app-handoff
  (deferred-login) contract models this package owns (carrier codec + mint/redeem
  wire shapes).
- `package:diene_e2e/test_helper.dart` — the **dependency-light** test harness:
  `StubServer`, the shared `AppHandoffStub` fixture, `Journey`/
  `DeferredLoginJourney` drivers, and plain-throw assertion helpers, plus the
  member `test_helper.dart` re-exports that exist. It has no test-framework
  dependency, so importing it never pulls `test`/`matcher` into a consumer's
  production graph.

## The shared deferred-login fixture

There is exactly ONE app-handoff fixture, defined by the C0 §7 contract. This
package **consumes** it — it ships the carrier codec + wire models and a
canonical `AppHandoffStub` that MOUNTS the mint/redeem behaviour onto the generic
`StubServer`. It deliberately does not build a second, dedicated app-handoff
server. The stub enforces the contract that matters for consumer journeys:
single-use nonces and one indistinguishable `AppHandoffExpired` (410) response
for every failure mode (missing, expired, replayed, deleted, suspended, or
email-rebound), so no account-state oracle leaks.

## Usage sketch

```dart
import 'package:diene_e2e/diene_e2e.dart';
import 'package:diene_e2e/test_helper.dart';

final server = await StubServer.start();
final stub = AppHandoffStub(problemTypeUri: '<c0 §2 type uri>')
  ..addUser(const AppHandoffUser(sub: 'u1', primaryEmail: 'a@b.com'))
  ..mintingUser = const AppHandoffUser(sub: 'u1', primaryEmail: 'a@b.com');
stub.mount(server);

final driver = DeferredLoginJourney(baseUrl: server.baseUrl, platform: 'android');
final result = await driver.redeemCarrier(installReferrerString);
// result.outcome is redeemed or interactiveFallback.
```

## Deliberate deltas vs `lib/bun/e2e`

The dart e2e is the frontend-only twin of the bun e2e. Documented differences:

| Dimension             | `lib/bun/e2e`                                           | `diene_e2e` (this package)                                                                                                               |
| --------------------- | ------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Members bundled       | 9 (incl. `otel`, `standard-config`)                     | 7 — NO `otel`, NO `standard-config` (dart is frontend-only; telemetry rides Faro; engine-owned config blocks, no standard-config member) |
| Re-export mechanism   | subpath exports (`@atomicloud/diene.e2e/result`)        | Dart libraries: runtime barrel `diene_e2e.dart`; helper barrel `test_helper.dart`                                                        |
| Test-helper packaging | subpath `…/test-helper`, optional peerDeps              | dependency-light sub-library `package:diene_e2e/test_helper.dart` (no test-framework deps)                                               |
| Harness glue          | Garden preview-env resolver + Bruno env glue            | consumer fixtures, stub server, journey drivers, and the shared C0 app-handoff fixture consumption                                       |
| Telemetry harness     | otel interface mocks re-exported (no FakeOtlpCollector) | none — no otel member at all                                                                                                             |
| Version-train ranges  | tilde (`~`) npm ranges                                  | pub caret/version constraints (wired at integration)                                                                                     |

## Integration-held seams

The seven L-dart members are built on parallel branches and are not yet published
packages, so their runtime re-exports (`diene_e2e.dart`) and test-helper
re-exports (`test_helper.dart`) are documented seams, not live `export` lines.
Wiring them — and the flutter-base E4 dogfood swap-in that deletes the in-app
copies — is conductor-owned integration work performed once the member packages
land and are stacked.
