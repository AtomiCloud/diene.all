# Auth engine (Dart)

`diene_auth_engine` is the frontend auth engine for the Diene Dart family. It
implements the C0 contract surface for Flutter clients: Logto flows,
per-resource tokens, multi-backend claims-first onboarding, deferred login,
returnTo continuation, the sign-up-only landscape selector, and the
engine-owned config block schema.

## Concepts

### Provider + retriever seams

- `AuthProvider` is the IdP seam. `LogtoAuthProvider` is the only v1
  implementation; consumers and tests fake the seam without the Logto SDK.
- `IAuth` (`AuthCoordinator`) is the retriever seam api-engine dogfoods. It
  caches one token per `ResourceKey`, refreshes when expiry nears, and is
  single-flight: concurrent callers for the same key await one acquisition.
- `fetchAllTokens` is the eager all-token batch (C0 §8): it dedups by full
  `ResourceKey`, starts every acquisition before awaiting, and returns one
  terminal entry per requested key. Lazy first-call acquisition is not allowed.

### Token lifecycle

`SessionController` enforces the C0 §12 lifetimes: access ≤ 10 minutes, refresh
≤ 14 days. A refresh that changes the family or re-returns the same refresh
token is reuse/theft and signs the session out. `onAppOpen` silently re-mints.

### Multi-backend onboarding

`OnboardingMachine` runs the C0 §8 claims-first state table per backend:

1. `bootstrapping` — resolve the backend's token batch.
2. If every required resource token carries the exact `<platform>_<service>`
   registration claim (JSON string `"true"`) → `ready`, or `needsOnboarding`
   when a declared app onboarding claim is absent.
3. Otherwise one `GET /User/Me`; `404` → `POST /User`; any `2xx`/`409` is
   create-or-ok; every other status/transport failure → `error`.
4. Force-refresh all resource tokens and re-check the claim; still absent →
   `error` (`OnboardingClaimMissing`).
5. A later `401`/`404` on an owned resource → `error`, never a second detect.

`MultiBackendOnboarding` holds one machine per backend — independent phases, no
cross-backend bleed.

### Deferred login

`DeferredLoginClient` reads the carrier (`atomi-app-handoff:v1:<nonce>`), marks
the referrer processed / clears the clipboard before redeem, redeems against
`POST {mount}/redeem`, and returns `one_time_token` + `login_hint` for
`signIn(extraParams:)`. Absent/invalid carrier or the generic `AppHandoffExpired`
(410) response falls back to interactive login — no retry loop.

### Home claim and landscape selector

`HomeClaimResolver` checks the home landscape on every sign-in (C0 §13):
present → route home; absent → the Doc B `LandscapeSelectorClient` (sign-up
only) fetches names + metadata, pings each region by convention, and picks the
fastest healthy one. Doc B carrying any address/issuer is rejected as untrusted.

### Config and baked issuer

`AuthEngineConfig` is the engine-owned `authEngine` block; the family `config`
lib merges and validates it. The OIDC issuer is a required, build-time-baked key
— never doc-sourced. The nonce TTL (15m) and one-time-token lifetime (120s) are
fixed contract constants, not schema knobs.

## Parity deltas vs `lib/bun/auth-engine`

| Area                                       | Bun                               | Dart                                                                                                                             |
| ------------------------------------------ | --------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| Server mint/redeem module                  | Present (`AppHandoffService`)     | Absent — mint/redeem is server-owned; Dart ships only the mobile client                                                          |
| Web-side handoff initiator/carrier builder | Present                           | Absent — Dart is the mobile receiver (carrier reader + redeem)                                                                   |
| Rescue router / Doc C                      | In api-engine/frontend-utils      | Not here — lives in `diene_auth_engine`'s sibling api-engine                                                                     |
| SSR returnTo helpers                       | Server + client                   | Client only (Flutter routing)                                                                                                    |
| Refresh rotation                           | Provider-surfaced refresh tokens  | Logto SDK owns rotation internally; the session reuse guard is exercised via fakes and applies to any refresh-surfacing provider |
| Result surface                             | `Result<T,E>`                     | Sealed `Result<T>` (C0 §5 combinator-name parity)                                                                                |
| Telemetry                                  | otel                              | None (Faro via flutter-base)                                                                                                     |
| FGA / server guards                        | Dropped / nullable-userId pattern | Client-only; no guard surface                                                                                                    |

## Dependency stacking

This package is built in an isolated lane, so it **self-carries** the minimal
`Result`/`Problem` contract types it needs (`lib/src/contracts/`). When the
conductor stacks the Dart family after all eight branches return, those files
are deleted and their imports repoint at the real `diene_result` /
`diene_problems` packages; the self-carried surface is a strict subset so the
swap is mechanical. The `AuthEngineConfig` block is consumed by the real
`diene_config` merger/validator at that point. No dependency stacking, mirror
publication, or downstream consumption happens in this lane.
