# Changelog

All notable changes to this package are documented here. Releases are managed
from conventional commits by the repository release workflow.

## 1.0.0

- Add the Logto sign-in surface: the `AuthProvider` seam with its only v1
  implementation `LogtoAuthProvider`, and `SessionController` owning the token
  lifecycle — interactive `signIn` (with deferred-login `extraParams`), rotating
  `refresh` with reuse detection, the silent `onAppOpen` re-mint, and `signOut`.
- Enforce the C0 §12 token lifetimes rather than trusting them: access tokens at
  most 10 minutes, refresh tokens at most 14 days rotating, re-mint on open
  (`TokenLifetimes`). A provider handing back a longer-lived token is rejected.
- Add per-resource tokens: `ResourceKey` as the full
  `(platform, landscape, service, resourceName)` identity whose `audience` is the
  per-landscape LPSM JWT `aud`, plus the `IAuth` retrieval seam and
  `AuthCoordinator` with a per-key cache, expiry-aware refresh, single-flight
  refresh-race handling, and the eager `fetchAllTokens` batch.
- Add the claims-first onboarding phase machine, **keyed per backend**:
  `RegisteredBackend` / `BackendRegistry` declare the client tree, and
  `MultiBackendOnboarding` runs one independent `OnboardingMachine` per backend
  from a single deduplicated registry-union acquisition. There is deliberately
  no singleton onboarded flag.
- Inspect the exact C0 §8 registration claim (`<platform>_<service>` with the
  JSON string `"true"`) as the gating truth everywhere (`Claims`); use
  `GET /User/Me` only for the absent-claim create-time race (`404` → `POST /User`,
  tolerating `409`) and treat a later `401`/`404` as an ordinary error via
  `markStaleClaim()`.
- Add the deferred-login mobile client (C0 §7): `AppHandoffCarrier` parsing for
  the canonical `atomi-app-handoff:v1:<nonce>` text, the Android Install Referrer
  field, and the iOS clipboard; `DeferredLoginClient` marking the carrier
  processed before redeem; `HttpAppHandoffApi` against `POST {mount}/redeem`; and
  the single no-oracle `appHandoffExpired` failure.
- Add returnTo deeplink continuation (`ReturnTo`): capture, login-redirect
  construction, and post-login resolution preserving path **and** query exactly,
  rejecting absolute, protocol-relative, and back-slash open-redirect inputs.
- Add the sign-up-only Doc B landscape selector (C0 §10):
  `LandscapeSelectorDoc` recursively rejects any address/issuer/URL leak at any
  depth, `LandscapeSelectorClient` pings each listed region and picks the fastest
  healthy one, and `HttpLandscapeSelectorSource` enforces the baked
  endpoint-suffix allowlist before fetching.
- Add C0 §13 home-claim resolution (`HomeClaimResolver`): the authoritative JWT
  `home_landscape` claim decides the home, the Doc B selector runs only when it is
  absent, the local `HomeClaimStore` is a non-authoritative mirror, and the
  post-OnboardSync claim is confirmed from a force-fresh claim-bearing token —
  failing closed rather than mirroring a local selection.
- Add `SignInCoordinator` tying the full flow together: resolve → login → re-read
  the issued claim → per-backend onboarding → confirm the written home claim →
  resume the exact returnTo route.
- Export the engine-owned `authEngine` config block schema next to the code that
  reads it (`AuthEngineConfig`, `AppHandoffConstants`); the `config` lib composes
  and validates it and never owns it.
- Ship the dependency-light `test_helper.dart` sub-library: fake IdP/token seams,
  per-backend onboarding-phase fakes, deferred-login carrier/redeem stubs, Doc B
  and home-claim fakes, `AuthFixtures` builders, and plain-throw `AuthExpect`
  assertions with no test-framework dependency.
- Depend on the Flutter SDK — the one deliberate deviation from the pure-Dart
  siblings, recorded with its two `dev_dependencies` consequences and the
  cross-family parity deltas in `doc/diene_auth_engine.md`.
