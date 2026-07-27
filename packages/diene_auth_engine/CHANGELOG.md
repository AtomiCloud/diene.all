# Changelog

All notable changes to this package are documented here. Releases are managed
from conventional commits by the repository release workflow.

## [1.0.1](https://github.com/AtomiCloud/diene.dart_auth_engine/compare/v1.0.0...v1.0.1) (2026-07-27)

### 🐛 Bug Fixes 🐛

- **dart-lib:** make the released changelog formatter-clean at generation ([#121](https://github.com/AtomiCloud/diene.dart_auth_engine/issues/121)) ([59a812b](https://github.com/AtomiCloud/diene.dart_auth_engine/commit/59a812bf5b78e986dee16c47e4da90f18b20bd7c))
- **auth-engine:** take the dart-lib changelog fix before release ([6331ea2](https://github.com/AtomiCloud/diene.dart_auth_engine/commit/6331ea267e9c26c83b0aae19c9b27fe9905f562e)), closes [#121](https://github.com/AtomiCloud/diene.dart_auth_engine/issues/121)

## 1.0.0 (2026-07-27)

### 📜 Documentation 📜

- **auth-engine:** package docs, usage skill, and parity notes ([24d1ec9](https://github.com/AtomiCloud/diene.dart_auth_engine/commit/24d1ec9d4652383f6b2f4d71cf3c68170e5fd13f))
- **auth-engine:** runnable package example ([988209e](https://github.com/AtomiCloud/diene.dart_auth_engine/commit/988209e368bbe5fc8c6dff332c1b4661666dd7ba))

### ✨ Features ✨

- **shared:** add agnostic standards payload ([2d65acb](https://github.com/AtomiCloud/diene.dart_auth_engine/commit/2d65acb118ebcc797cca0f13b0d9e979e7a8c29c))
- **probes:** add nix root suite ([27e4184](https://github.com/AtomiCloud/diene.dart_auth_engine/commit/27e41843f06e38cfcc26a516c05f4ae4fb294ac0))
- **dart-lib:** add pure-Dart publishable library template package ([47a4837](https://github.com/AtomiCloud/diene.dart_auth_engine/commit/47a4837f54f7ad0342a4539ff1320c4f94d7df71))
- **probes:** add shared authoring helpers ([f20d53f](https://github.com/AtomiCloud/diene.dart_auth_engine/commit/f20d53f805564fe21e0ee32084fc49f2973a50e4))
- **auth-engine:** bind C0 conformance to the frozen identity fixture ([a1e2240](https://github.com/AtomiCloud/diene.dart_auth_engine/commit/a1e224069105220a2f10cb8074675e783b8bc991))
- materialize atomi/nix sample (yes_basic_yes_llm) as chain root ([24105ef](https://github.com/AtomiCloud/diene.dart_auth_engine/commit/24105ef4948ff884353011be24b915f69c7c8382))
- materialize workspace spine baseline ([f74cf31](https://github.com/AtomiCloud/diene.dart_auth_engine/commit/f74cf3179989e12f662b1c98061aeb2d4803f563))
- **shared-wo-docker:** remove Docker axis ([b125b74](https://github.com/AtomiCloud/diene.dart_auth_engine/commit/b125b74a556f5b5f5d82ef973a79c80079c5b63e))
- **shared-wo-docker-helm:** remove Helm axis ([e01fe36](https://github.com/AtomiCloud/diene.dart_auth_engine/commit/e01fe368b9fe30bee238c809a58444c9170998f2))
- **auth-engine:** transplant onto dart-lib as a Flutter package ([267d8a4](https://github.com/AtomiCloud/diene.dart_auth_engine/commit/267d8a4e6b1eda71669b7c34466461e4e69b5d0b))
- **dart-lib:** wire Dart CI, release, and OIDC publish machinery ([770b8ec](https://github.com/AtomiCloud/diene.dart_auth_engine/commit/770b8ec512e44ccfb0495daebbcad081a65344c5))

### 🐛 Bug Fixes 🐛

- **probes:** attribute actionlint smoke overlap ([bfb0271](https://github.com/AtomiCloud/diene.dart_auth_engine/commit/bfb02717d6eca8c86f617efe50286008da328fe1))
- **nix:** check precommit from repository root ([c6046ac](https://github.com/AtomiCloud/diene.dart_auth_engine/commit/c6046ac3d877f2fed40073ff333fe2b877b778a8))
- **nix:** enforce root formatter probes ([3b4188a](https://github.com/AtomiCloud/diene.dart_auth_engine/commit/3b4188aa9797c14f10fb448e68cdeefeb9ae231e))
- **probes:** isolate cross-template mutations ([f8169d0](https://github.com/AtomiCloud/diene.dart_auth_engine/commit/f8169d002a3db773f638a01a280c0170781164f5))
- **auth-engine:** repair coverage collection and ledger partition ([49356c3](https://github.com/AtomiCloud/diene.dart_auth_engine/commit/49356c3c4ac07bbb08cfeda435b333aa7e05152c))
- **auth-engine:** restore deadcode entrypoint, give pana Flutter SDK ([07ab458](https://github.com/AtomiCloud/diene.dart_auth_engine/commit/07ab458096738bad37410a45ddcb6cba7028458c))
- **dart-lib:** use credentialed pub.dev publishing ([#107](https://github.com/AtomiCloud/diene.dart_auth_engine/issues/107)) ([796d025](https://github.com/AtomiCloud/diene.dart_auth_engine/commit/796d0252fa94b14e2ec418fd9c70e3f75e792813))

### 🧪 Tests 🧪

- **dart-lib:** add TEMPLATE-ONLY CyanPrint probe matrix ([6a1f748](https://github.com/AtomiCloud/diene.dart_auth_engine/commit/6a1f748e2960ae7cd07d768eec81bdbbd68c0ed7))
- **auth-engine:** close the meta coverage ledger at 100% ([1e1c79c](https://github.com/AtomiCloud/diene.dart_auth_engine/commit/1e1c79c19d49d498f42a63aa15032dc0b9d53185))
- **auth-engine:** cover the last reachable unit ledger lines ([751b80e](https://github.com/AtomiCloud/diene.dart_auth_engine/commit/751b80edcc34ed12bcbb1660b8ecf6c315f477d1))
- **auth-engine:** cover the LogtoAuthProvider token seams ([a1fb2b2](https://github.com/AtomiCloud/diene.dart_auth_engine/commit/a1fb2b278f52e16e286ee40be97c72db1f70c9ac))
- **auth-engine:** cover the residual unit ledger gaps ([080802d](https://github.com/AtomiCloud/diene.dart_auth_engine/commit/080802ddec3399b3e2be3beb1200ff6d638a2ee4))
- **auth-engine:** cover the three zero-coverage platform adapters ([106749c](https://github.com/AtomiCloud/diene.dart_auth_engine/commit/106749ce16d86c584726d6e7115badc6bc86642d))
- **dart-lib:** fix dead-code and credential-policy mutation sabotages ([f1737e9](https://github.com/AtomiCloud/diene.dart_auth_engine/commit/f1737e95d097716c53139fe2b64822dddb71aa6b))
- **dart-lib:** fix deadcode-whole-package sabotage target ([226e3d2](https://github.com/AtomiCloud/diene.dart_auth_engine/commit/226e3d2de16ff2ce5b206f434e12fcac9fd79354))
- **dart-lib:** fix probe baselines for gitlint hook and pana ([1519f9a](https://github.com/AtomiCloud/diene.dart_auth_engine/commit/1519f9a4939ab0811cac827e1c36d2eaa2da1d05))
- **auth-engine:** record the ClipboardCarrierReader constructor ([387f5da](https://github.com/AtomiCloud/diene.dart_auth_engine/commit/387f5da728b7eecb66993446e677aeecc7cd36f6))
- **dart-lib:** restore workspace deps for skills-freshness sandbox ([9a2e5bf](https://github.com/AtomiCloud/diene.dart_auth_engine/commit/9a2e5bffc1e4ff36d259c1abc2b5021a7b7bca87))

### Release highlights

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
