---
name: diene-auth-engine-usage
description: Use when consuming package:diene_auth_engine — wiring Logto sign-in and per-resource tokens, gating on the per-backend claims-first onboarding phases, redeeming a deferred-login carrier, resolving the home landscape, or reaching for the dependency-light fakes and AuthExpect assertions in tests.
---

# diene_auth_engine usage

Import only the public barrel; never reach into `lib/src`:

```dart
import 'package:diene_auth_engine/diene_auth_engine.dart';
```

## Wiring the seams

1. Build the config from the engine-owned block the `config` lib hands over:
   `AuthEngineConfig.fromBlock(block['authEngine']!)`. The OIDC `issuer` is
   **baked build-time** — never source it from a doc.
2. Construct `LogtoAuthProvider(config: ..., primaryResource: ...)` (the only v1
   provider) and wrap it in `AuthCoordinator(provider: ...)` — the `IAuth` seam
   `api-engine` consumes.
3. `SessionController(provider: ...)` owns the token lifecycle: `signIn`,
   `refresh`, `onAppOpen` (the silent re-mint), `signOut`. Lifetimes are
   **enforced**, not trusted — a provider handing back a longer-lived token is
   rejected.

Take the narrowest seam a component needs. A widget gating on readiness takes the
phase map, not the whole coordinator.

## Per-resource tokens

`ResourceKey(platform:, landscape:, service:, resourceName:)` is the full
identity; every component must be a lowercase DNS label. `mapKey` is the
canonical client-map key and `audience` is the JWT `aud`. Use
`auth.tokenFor(key)` on the hot path (cached, single-flight) and
`auth.fetchAllTokens(keys)` for the eager batch — it starts every acquisition
before awaiting any, so do not loop `tokenFor` to emulate it.

## Multi-backend onboarding (keyed per backend)

- Declare each backend with `RegisteredBackend(backendId:, resources:,
onboardingResource:, appOnboardingClaim:)` and collect them in a
  `BackendRegistry`.
- Run `MultiBackendOnboarding(...).runAll()`. Each backend has an independent
  `bootstrapping / needsOnboarding / ready / error` phase — gate a route on the
  backend(s) it needs. **Ready on A while B onboards is normal**; there is
  deliberately no singleton onboarded flag to check.
- Registration truth is the exact `<platform>_<service>` JWT claim whose value is
  the string `"true"`. `GET /User/Me` is **only** the absent-claim create-time
  race (`404` → `POST /User`, tolerate `409`). A later `401`/`404` is a normal
  error, not a second detector — call `markStaleClaim()` and do not re-run
  `/User/Me`.

## Deferred login

- Give `DeferredLoginClient` an `AppHandoffApi` (`HttpAppHandoffApi`), a
  `DeviceInfo` (telemetry only — it must not affect identity), and a carrier
  source: `CallbackInstallReferrerSource` on Android,
  `ClipboardCarrierReader` on iOS.
- `prepare()` returns `DeferredLoginReady(extraParams)` — pass those straight to
  `SessionController.signIn(extraParams:)` — or `DeferredLoginFallback`, which
  means "log in normally". Never log or persist the nonce, and do not add a
  carrier retry loop.

## Home landscape and returnTo

- `HomeClaimResolver(claimReader:, selector:, store:).resolve()`: the
  **authoritative** JWT `home_landscape` claim decides the home
  (`jwtHomeClaimReader(provider.idToken)`); an absent claim runs the Doc B
  selector, which is **sign-up only, never a routing layer**. The store is a
  non-authoritative mirror — never consult it to choose the home. `commit()` only
  mirrors a value the JWT already made authoritative.
- Use `ReturnTo.buildLoginRedirect` / `ReturnTo.continueFrom` to resume the exact
  protected route after login (path **and** query preserved). Absolute and
  protocol-relative targets are rejected as open redirects.
- `SignInCoordinator` runs the whole ordering: resolve → login → re-read the
  issued claim → per-backend onboarding → (sign-up only) confirm the
  post-OnboardSync claim from a **force-fresh** token via `confirmedHome()` →
  continuation. It never persists the Doc B selection as a claim; an unconfirmed
  claim, a missing forced token, or an onboarding error returns an explicit
  `Problem` (fail-closed).
- Wire `LogtoAuthProvider(claimTokenRefresher: …)` so `freshClaimToken()` can
  guarantee a fresh claim-bearing JWT after OnboardSync. Unwired, it returns
  `null` to fail closed.

## TestHelper

`import 'package:diene_auth_engine/test_helper.dart';` — that is what it is for.
No test framework, matcher, or mocking package:

- **Fakes**: `FakeAuthProvider`, `FakeAuth`, `FakeUserDirectory`,
  `FakeAppHandoffApi`, `FakeLandscapeSelectorSource`, `FakeRegionPinger`,
  `MemoryHomeClaimStore`, `FakeInstallReferrerSource`,
  `FakeClipboardCarrierSource`.
- **Builders**: `AuthFixtures.jwt`, `registeredJwt`, `unregisteredJwt`,
  `sessionTokens`, `resourceToken`, `resourceKey`.
- **Assertions**: `AuthExpect.ok` / `err` / `errType` / `some` / `none` /
  `phase` / `status`, throwing `AuthAssertionError`.

```dart
final FakeAuthProvider provider = FakeAuthProvider(
  onSignIn: () => AuthFixtures.sessionTokens(now: now),
  idTokenValue: AuthFixtures.registeredJwt(key),
);
AuthExpect.ok(await SessionController(provider: provider, now: () => now).signIn());
```

Do: script the seams with fakes and assert with `AuthExpect`. Don't: reach for a
real IdP or network in a unit test, or add a test-framework dependency to the
helper — `scripts/validate/dart-package.sh` fails the build if you do.

See `patterns.md` for the fake-scripting model, the claim-fixture recipes, the
meta-tier convention, and the documented parity deltas against the `lib/bun`
siblings.
