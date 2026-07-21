---
name: diene-auth-engine-usage
description: Use when wiring Logto auth, per-resource tokens, multi-backend claims-first onboarding, deferred login, returnTo continuation, or the landscape selector with diene_auth_engine in a Flutter app.
---

`diene_auth_engine` is the Diene Dart-family frontend auth engine. Import the
public surface with `package:diene_auth_engine/diene_auth_engine.dart` and the
dependency-light fakes/builders/assertions with
`package:diene_auth_engine/test_helper.dart`.

## Wiring the seams

1. Build `AuthEngineConfig.fromBlock(config['authEngine'])`. The OIDC `issuer`
   is baked build-time — never source it from a doc.
2. Construct `LogtoAuthProvider(config: ..., primaryResource: ...)` (the only v1
   provider) and wrap it in `AuthCoordinator(provider: ...)` (the `IAuth` seam
   api-engine consumes).
3. `SessionController(provider: ...)` owns the token lifecycle. Call `signIn`,
   `refresh`, `onAppOpen` (silent re-mint), `signOut`. Lifetimes are enforced,
   not trusted.

## Multi-backend onboarding (keyed per backend)

- Declare each backend with `RegisteredBackend(backendId, resources,
onboardingResource, appOnboardingClaim?)`; collect them in a
  `BackendRegistry`.
- Run `MultiBackendOnboarding(...).runAll()`. Each backend has an independent
  `bootstrapping / needsOnboarding / ready / error` phase — gate a route on the
  backend(s) it needs. Ready on A while B onboards is normal.
- Registration truth is the exact `<platform>_<service>` JWT claim (string
  `"true"`). `GET /User/Me` is only the absent-claim create-time race
  (`404` → `POST /User`, tolerate `409`); a later `401`/`404` is a normal error,
  not a second detector — call `markStaleClaim()`.

## Deferred login

- Give `DeferredLoginClient` an `AppHandoffApi` (`HttpAppHandoffApi`), a
  `DeviceInfo`, and a carrier source (`CallbackInstallReferrerSource` on
  Android, `ClipboardCarrierReader` on iOS).
- `prepare()` returns `DeferredLoginReady(extraParams)` — pass those to
  `SessionController.signIn(extraParams:)` — or `DeferredLoginFallback` (fall
  back to normal login). Never log/persist the nonce; there is no retry loop.

## Home landscape + returnTo

- `HomeClaimResolver(claimReader:, selector:, store:).resolve()`: the
  AUTHORITATIVE JWT `home_landscape` claim decides the home (`claimReader` /
  `jwtHomeClaimReader(provider.idToken)`); an absent claim runs the Doc B
  selector (sign-up only). The store is a NON-authoritative mirror — never
  consulted to choose the home. `commit(landscape)` only mirrors a value the JWT
  already made authoritative.
- Use `ReturnTo.buildLoginRedirect` / `ReturnTo.continueFrom` to resume the
  exact protected route after login. Absolute/protocol-relative targets are
  rejected as open redirects.
- `SignInCoordinator` ties resolve → login → re-read issued claim → onboarding →
  (sign-up only) refresh + CONFIRM the post-OnboardSync JWT claim → continuation.
  It never persists the Doc B selection as a claim; a still-missing claim or an
  onboarding error returns an explicit Problem.

## TestHelper

`import 'package:diene_auth_engine/test_helper.dart';` gives:

- Fakes: `FakeAuthProvider`, `FakeAuth`, `FakeUserDirectory`,
  `FakeAppHandoffApi`, `FakeLandscapeSelectorSource`, `FakeRegionPinger`,
  `MemoryHomeClaimStore`, `FakeInstallReferrerSource`,
  `FakeClipboardCarrierSource`.
- Builders: `AuthFixtures.jwt`, `registeredJwt`, `sessionTokens`,
  `resourceToken`, `resourceKey`.
- Plain-throw assertions: `AuthExpect.ok/err/errType/some/none/phase/status`.

Do: script the seams with fakes and assert with `AuthExpect`. Don't: reach for a
real IdP/network in unit tests, or add test-framework deps to the helper.

See the auth standard for concepts, the C0 §7/§8/§10/§12/§13 contract, and the
`lib/bun/auth-engine` parity deltas.
