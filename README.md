# diene_auth_engine

Frontend auth engine for the AtomiCloud **Diene** Dart family.

`diene_auth_engine` is a Flutter package that ships the client-side auth
machinery every Diene mobile app reuses:

- **Logto flows + per-resource tokens** behind an `AuthProvider` seam, with an
  expiry-aware, single-flight per-resource token cache (`IAuth`).
- **Token lifecycle** — access = 10 minutes, refresh = 14 days rotating with
  reuse detection, silent re-mint on app open (C0 §12).
- **Multi-backend, claims-first onboarding** — one app onboards to many
  backends, each with an independent `bootstrapping / needsOnboarding / ready /
error` phase machine (C0 §8, no singleton flag).
- **Deferred-login mobile client** — Install Referrer / clipboard carrier read,
  redeem against `POST {mount}/redeem`, and `signIn(extraParams:)`.
- **returnTo deeplink continuation** — resume the exact protected route (path +
  query) after login, with open-redirect rejection.
- **Sign-up-only landscape selector** — the Doc B client (names + metadata
  only), ping-and-pick with a `home_landscape`-claim fast path (C0 §10/§13).
- **Engine-owned config block schema** — the `authEngine` block, validated by
  the family `config` lib; the OIDC issuer is baked build-time, never
  doc-sourced.

Dart is **frontend-only**: there is no OpenTelemetry surface here — telemetry
rides Faro through flutter-base.

## Install

```yaml
dependencies:
  diene_auth_engine: ^0.0.0
```

## Usage

```dart
import 'package:diene_auth_engine/diene_auth_engine.dart';
```

See the shipped skill `skills/diene-auth-engine-usage/SKILL.md` and
[docs/standards/auth/index.md](docs/standards/auth/index.md) for wiring
(per-backend onboarding, deferred login, retriever/provider seams) and the
`lib/bun/auth-engine` parity deltas.

## TestHelper

A dependency-light TestHelper ships in the same package:

```dart
import 'package:diene_auth_engine/test_helper.dart';
```

It carries fakes (IdP/provider, retrievers, deferred store, per-backend phase
fakes), token/claims builders, and plain-throw assertions — no test-framework
dependencies.

## Development

Managed by Nix; run `direnv allow` once, then use `pls` tasks:

- `pls test` — unit, conformance, and meta tests.
- `pls test:coverage` — unit coverage ledger.
- `pls test:meta` — meta tier over the TestHelper.
- `pls deadcode` — two-pass dead-code gate.
- `pls publish:dryrun` — package hygiene.
- `pls gates` — the full host-safe gate chain.
