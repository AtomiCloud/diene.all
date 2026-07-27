# diene_auth_engine

[![pub package](https://img.shields.io/pub/v/diene_auth_engine.svg)](https://pub.dev/packages/diene_auth_engine)
[![CI](https://github.com/AtomiCloud/diene.dart_auth_engine/actions/workflows/ci.yaml/badge.svg)](https://github.com/AtomiCloud/diene.dart_auth_engine/actions/workflows/ci.yaml)
[![unit coverage](https://codecov.io/gh/AtomiCloud/diene.dart_auth_engine/graph/badge.svg?flag=unit)](https://codecov.io/gh/AtomiCloud/diene.dart_auth_engine)
[![meta coverage](https://codecov.io/gh/AtomiCloud/diene.dart_auth_engine/graph/badge.svg?flag=meta)](https://codecov.io/gh/AtomiCloud/diene.dart_auth_engine)

The Diene Dart family's **frontend auth engine**. It owns the Logto sign-in
flows, the token lifecycle, per-resource access tokens, the claims-first
onboarding phase machine (keyed **per backend**), the deferred-login mobile
client, returnTo deeplink continuation, the engine-owned config block schema,
and the sign-up-only Doc B landscape selector.

Every fallible surface returns a `Result` carrying an RFC 9457 `Problem` — the
engine never throws to signal an expected failure. The client is **claims-first**
everywhere: per-resource JWT claims are the gating truth, and `GET /User/Me` is
only the absent-claim create-time race.

```dart
import 'package:diene_auth_engine/diene_auth_engine.dart';

// The `authEngine` block the `config` lib hands over. `issuer` is BAKED
// build-time config — never sourced from an edge doc.
final AuthEngineConfig config = AuthEngineConfig.fromBlock(block['authEngine']!);

final ResourceKey api = ResourceKey(
  platform: 'lithium',
  landscape: 'lapras',
  service: 'api',
  resourceName: 'root',
);

final LogtoAuthProvider provider = LogtoAuthProvider(
  config: config,
  primaryResource: api,
);
final IAuth auth = AuthCoordinator(provider: provider);
final SessionController session = SessionController(provider: provider);
```

```dart
// In tests, use the shipped dependency-light fakes — no mocking framework.
import 'package:diene_auth_engine/test_helper.dart';

final FakeAuthProvider provider = FakeAuthProvider(
  onSignIn: () => AuthFixtures.sessionTokens(now: DateTime.utc(2026, 7, 26)),
);
final SessionTokens tokens = AuthExpect.ok(await session.signIn());
```

## Public surface

| Area                   | Members                                                                                                                                                                                                                           |
| ---------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| IdP seam               | `AuthProvider`, `LogtoAuthProvider`                                                                                                                                                                                               |
| Token retrieval seam   | `IAuth`, `AuthCoordinator`                                                                                                                                                                                                        |
| Session lifecycle      | `SessionController`, `SessionStatus`, `TokenLifetimes`                                                                                                                                                                            |
| Tokens                 | `ResourceKey`, `SessionTokens`, `ResourceToken`, `ResourceTokenEntry`                                                                                                                                                             |
| Claims                 | `Claims` (`homeLandscape`, `decode`, `registrationKey`, `hasRegistration`, `home`)                                                                                                                                                |
| Onboarding             | `RegisteredBackend`, `BackendRegistry`, `OnboardingPhase`, `OnboardingMachine`, `MultiBackendOnboarding`, `UserDirectory`, `IdTokenReader`                                                                                        |
| Deferred login         | `AppHandoffCarrier`, `DeferredLoginClient`, `DeferredLoginOutcome` (`DeferredLoginReady` / `DeferredLoginFallback`), `InstallReferrerSource`, `ClipboardCarrierSource`, `ClipboardCarrierReader`, `CallbackInstallReferrerSource` |
| App-handoff wire       | `AppHandoffApi`, `HttpAppHandoffApi`, `DeviceInfo`, `RedeemResult`, `appHandoffExpired`, `AppHandoffConstants`                                                                                                                    |
| Home landscape (Doc B) | `HomeClaimResolver`, `HomeClaimReader`, `jwtHomeClaimReader`, `HomeClaimStore`, `HomeResolution`, `HomeResolutionKind`                                                                                                            |
| Landscape selector     | `LandscapeSelectorClient`, `LandscapeSelectorDoc`, `LandscapeEntry`, `LandscapeSelectorSource`, `HttpLandscapeSelectorSource`, `RegionPinger`, `HttpRegionPinger`, `PingUrlBuilder`                                               |
| returnTo               | `ReturnTo` (`queryKey`, `capture`, `buildLoginRedirect`, `resolve`, `continueFrom`)                                                                                                                                               |
| Orchestration          | `SignInCoordinator`, `SignInResult`                                                                                                                                                                                               |
| Config                 | `AuthEngineConfig` (incl. `blockSchema`, `redeemPath`, `allowsUrl`)                                                                                                                                                               |
| Self-carried contracts | `Result` / `Success` / `Failure`, `Option` / `Some` / `None`, `Problem`, `problemTypeUri`                                                                                                                                         |

## What this package deliberately does NOT own

- **No routing layer.** The Doc B landscape selector runs **once, at sign-up**.
  After that the client holds exactly one hostname (its home landscape's).
- **No singleton "onboarded" flag.** Every registered backend runs its own
  independent `bootstrapping / needsOnboarding / ready / error` machine; ready on
  A while B onboards is normal.
- **No dormant rescue router.** Doc A / Doc C and the rescue router belong to
  `lib/dart/api-engine`.
- **No otel surface.** Dart is frontend-only; telemetry rides Faro through
  `flutter-base`.
- **No config merging or validation.** This package exports its own block
  schema; the `config` lib is the sole merger/validator.
- **No UX-pattern widgets.** The five bun-frontend-utils mechanism-hook twins
  are documented in the parity section and mostly belong to `flutter-base`.

## Flutter dependency

Unlike the four pure-Dart siblings (`diene_result`, `diene_interfaces`,
`diene_core_utils`, `diene_problems`), this package depends on the **Flutter
SDK**. That is forced, not stylistic — see the
[package doc](doc/diene_auth_engine.md) for the full reasoning, the two
`dev_dependencies` consequences, and the recorded family precedent.

## TestHelper

`package:diene_auth_engine/test_helper.dart` ships the fake IdP/token seams
(`FakeAuthProvider`, `FakeAuth`), the per-backend onboarding-phase fakes
(`FakeUserDirectory`), the deferred-login carrier/redeem stubs
(`FakeAppHandoffApi`, `FakeInstallReferrerSource`, `FakeClipboardCarrierSource`),
the Doc B fakes (`FakeLandscapeSelectorSource`, `FakeRegionPinger`,
`MemoryHomeClaimStore`), the `AuthFixtures` builders, and the plain-throw
`AuthExpect` assertions. It depends on **no** test framework, matcher library, or
mocking package, so it adds nothing to a consumer's production dependency graph.

Read the [package doc](doc/diene_auth_engine.md) for the flow contracts, the
C0 §7/§8/§10/§12/§13 bindings, and the **cross-family parity checklist** against
the `lib/bun` siblings.

## Development

- `pls setup` resolves the workspace dependencies.
- `pls test` runs the unit, C0 conformance, and TestHelper meta suites.
- `pls test:coverage` enforces the separate unit and meta ledgers.
- `pls deadcode` runs the repository and production-only dead-code passes.
- `pls package:validate` runs the release guard, publish dry-run, and pana.
