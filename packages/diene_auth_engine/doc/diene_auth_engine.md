# diene_auth_engine contract

`diene_auth_engine` is the Diene Dart family's frontend auth engine. It owns the
Logto binding, the token lifecycle, per-resource tokens, the per-backend
claims-first onboarding phase machine, the deferred-login mobile client, returnTo
continuation, the engine-owned config block schema, and the sign-up-only Doc B
landscape selector — and nothing else.

Dart is frontend-only, so there is no otel surface here: telemetry rides Faro
through `flutter-base`.

## Owned surfaces

| Surface             | Boundary                                                   | Entry points                                                     |
| ------------------- | ---------------------------------------------------------- | ---------------------------------------------------------------- |
| IdP binding         | the Logto SDK, behind a fakeable interface                 | `AuthProvider`, `LogtoAuthProvider`                              |
| Session lifecycle   | one authenticated session's tokens                         | `SessionController`, `SessionStatus`, `TokenLifetimes`           |
| Token retrieval     | resolve a token per resource, with a cache on the hot path | `IAuth`, `AuthCoordinator`                                       |
| Resource identity   | the full LPSM coordinate and its JWT `aud`                 | `ResourceKey`, `SessionTokens`, `ResourceToken`                  |
| Claims inspection   | reading (never verifying) JWT payload claims               | `Claims`                                                         |
| Onboarding          | per-backend readiness, claims-first                        | `BackendRegistry`, `MultiBackendOnboarding`, `OnboardingMachine` |
| Deferred login      | store carrier → redeem → `signIn(extraParams:)`            | `DeferredLoginClient`, `AppHandoffCarrier`, `HttpAppHandoffApi`  |
| Home landscape      | which landscape is home, and who decides                   | `HomeClaimResolver`, `LandscapeSelectorClient`                   |
| Route continuation  | resume the exact protected route after login               | `ReturnTo`                                                       |
| Whole-flow ordering | the C0 §13 sign-in order                                   | `SignInCoordinator`                                              |
| Config block        | the engine's own schema, next to the code that reads it    | `AuthEngineConfig`, `AppHandoffConstants`                        |

## The failure contract

Every fallible surface returns `Result<T>` (or `Future<Result<T>>`) carrying a
`Problem` on the error arm. The engine does not throw to communicate an expected
failure — a bad carrier, an expired refresh token, an unreachable Doc B host, and
an unconfirmed home claim are all values.

The one deliberate exception is the `AuthProvider` seam itself: its methods may
throw, because they wrap a third-party SDK. `SessionController` and
`AuthCoordinator` are the boundary that converts those throws into problem-typed
`Result`s, so no consumer ever writes `try`/`catch` around the engine.

Three rules follow from the contract rather than from convenience:

- **Absence is not failure.** A missing deferred-login carrier yields
  `DeferredLoginFallback`, not an error — the app simply logs in interactively. An
  absent `home_landscape` claim yields `Success(null)` from
  `authoritativeHome()`, which is what routes a new user into the Doc B sign-up
  path.
- **Unconfirmable is failure.** `confirmedHome()` returning `null` after
  onboarding is turned into an explicit
  `urn:diene:problem:home-claim-unconfirmed` failure by the coordinator. The
  engine fails closed rather than mirroring a locally selected landscape as
  though the server had written it.
- **Redeem has no oracle.** Every app-handoff redeem failure — missing, expired,
  replayed, deleted, suspended, rebound, upstream — collapses to exactly
  `appHandoffExpired()` (`410`, `AppHandoffExpired`). The response never
  distinguishes account states.

## Token lifetimes (C0 §12)

`TokenLifetimes` mirrors `contracts/c0/cases/identity.json` →
`cases.tokenLifetimes` exactly: `accessMinutes: 10`, `refreshDays: 14`,
`refreshRotating: true`, `remintOnOpen: true`. They are fleet-wide constants, not
config knobs, and the C0 conformance tier asserts each against the fixture, so a
drift turns the suite red instead of shipping.

Lifetimes are **enforced, not trusted**. `SessionController._validateLifetime`
rejects any issued pair whose access lifetime exceeds 10 minutes or whose refresh
lifetime exceeds 14 days (and any already-expired pair). Rotation is what makes
reuse detection possible: a refresh that returns a different `refreshFamily`, or
re-returns the same refresh token, signs the session out with
`urn:diene:problem:refresh-reuse`. `onAppOpen()` re-mints the access token and
preserves the refresh token, so a fresh app session never trusts a cached access
token for its remaining TTL.

## Per-resource tokens (C0 §8, S7)

`ResourceKey = (platform, landscape, service, resourceName)`. Every component is
an explicit lowercase DNS label; none is inferred, and the constructor rejects
anything that is not one. `resourceName` occupies the M slot of the public LPSM
coordinate, so the Logto resource indicator / JWT `aud` is exactly
`https://<resourceName>.<service>.<platform>.<landscape>.cluster.atomi.cloud`
with no trailing slash. The canonical client-map key is
`platform/landscape/service/resourceName` (`mapKey`).

`AuthCoordinator` implements the `IAuth` seam that `api-engine` dogfoods:

- `tokenFor` serves the per-key cache while the token is still fresh under a
  30-second skew, and is **single-flight** — concurrent callers for the same key
  await one acquisition rather than racing the provider.
- `fetchAllTokens` is the eager all-token batch: it deduplicates the requested
  keys by full `ResourceKey`, starts acquisition for **every** key before
  awaiting any, and returns a total map with exactly one terminal entry per
  requested key. Lazy first-call acquisition is not permitted.
- `invalidate` / `invalidateAll` back the onboarding force-refresh path and
  sign-out.

## Per-backend claims-first onboarding (C0 §8, S20)

One client app onboards to **many** backends. `RegisteredBackend` declares a
stable `backendId`, the full `resources` it needs, which one
(`onboardingResource`) protects its `/User` surface, and optionally a separately
declared `appOnboardingClaim`. `BackendRegistry` holds them with unique ids and
exposes the deduplicated `resourceUnion`.

`MultiBackendOnboarding.runAll()` takes **one** registry snapshot, acquires the
deduplicated union **once**, then projects that single batch into per-backend
slices and runs each `OnboardingMachine` concurrently. A resource shared by two
backends is acquired once here, never once per backend.

Each machine walks the C0 §8 state table to a terminal phase:

1. `bootstrapping` — resolve this backend's complete token batch (the projected
   union slice, or a scoped acquisition for a standalone run). Any failed entry
   → `error`, isolated to this backend.
2. Every required resource token carries the exact registration claim →
   registered. If an `appOnboardingClaim` is declared and absent from the
   onboarding-resource token, the phase is `needsOnboarding`; otherwise `ready`.
3. The registration claim is absent from **any** required token → exactly one
   `GET /User/Me` with the onboarding-resource token. `200` means the row exists;
   `404` triggers `POST /User` with the raw ID token, and any `2xx` or `409` is
   create-or-ok. Every other status, or a transport throw, → `error`.
4. After GET `200` or an accepted POST, force-refresh **all** of this backend's
   resource tokens and re-check the exact claim. Present everywhere → step 2;
   still absent → `error` with `OnboardingClaimMissing` (`409`). This is the only
   claim-repair path.
5. `markStaleClaim()` handles the case where a claim was present and a later
   owned-resource call returned `401`/`404`. That is an ordinary authorization
   error: it enters `error` and **must not** re-run `/User/Me` or create. A stale
   claim is never a second detector.

There is deliberately **no singleton onboarded flag**. `phases` is a
`Map<String, OnboardingPhase>`, and UI gates wait only for the backend(s) a route
or module actually needs — ready on A while B onboards or errors is the normal
case, not a degraded one.

The registration claim itself is the exact C0 §8 key: `<platform>_<service>` with
both labels lowercased and every `-` replaced by `_`, and the value **must** be
the JSON string `"true"`. `Claims.hasRegistration` treats a missing key, `null`,
boolean `true`, or any other value as absent.

## Deferred login (C0 §7)

The mobile half of the app-handoff flow; `dotnet-api` hosts mint and redeem.

`AppHandoffCarrier` parses the canonical text `atomi-app-handoff:v1:<nonce>`
where the nonce is 32 random bytes RFC 4648 base64url **without** padding (43
ASCII characters). Three entry points, matching the three carrier shapes:
`parseCanonical`, `parseAndroidReferrer` (one
`app_handoff=<percent-encoded carrier>` field — zero or duplicate fields are
treated as absent, other campaign fields coexist), and `parseClipboard`
(canonical text with ASCII whitespace optionally trimmed).

`DeferredLoginClient.prepare()` prefers the Android Install Referrer when
present, then falls back to the iOS clipboard. It marks the referrer processed —
or clears the clipboard only if it still equals the captured value — **before**
redeeming, then redeems through `AppHandoffApi`. On success it returns
`DeferredLoginReady` carrying the `one_time_token` and `login_hint` extra params
for `SessionController.signIn(extraParams:)`. Anything else returns
`DeferredLoginFallback`, and the app logs in normally. The client never throws,
never logs or persists the nonce, and runs no carrier-specific retry loop.

`AppHandoffConstants` fixes the non-negotiable constants: a 15-minute nonce TTL,
a 120-second one-time-token lifetime (a fixed value, not a ceiling), and
`/app-handoff` as the **default** mount — the mount itself is configurable, and
`AuthEngineConfig.redeemPath` composes `{mount}/redeem` without doubling the
segment. `DeviceInfo` is telemetry only and must not affect identity or
authorization.

## Home landscape and the Doc B selector (C0 §10, §13)

The `home_landscape` claim is checked on **every** sign-in, not just the first.
`HomeClaimResolver` reads it through a `HomeClaimReader` —
`jwtHomeClaimReader(provider.idToken)` decodes the claim out of the provider's
current token:

- **Present** → that is the home. It is mirrored into the local store and
  returned as `HomeResolutionKind.fromClaim`. No Doc B fetch, no picker.
- **Absent** → the sign-up path runs the Doc B selector, returned as
  `HomeResolutionKind.selected`.

`HomeClaimStore` is a **non-authoritative mirror**. It is never consulted to
choose the home, so a stale or tampered cache cannot decide routing, and a
changed or removed Logto `custom_data.home_landscape` is always observed on the
next sign-in. Mirror writes are best-effort; a store failure never overrides the
JWT decision.

`LandscapeSelectorClient` is the Doc B client: fetch the doc, ping every listed
region concurrently, keep only the healthy ones, and pick the caller's
`preferred` name when it is healthy or the fastest otherwise. It is **SIGN-UP
ONLY** and never a routing layer — after sign-up the client holds exactly one
hostname, its home landscape's.

Doc B carries landscape **names + metadata only**.
`LandscapeSelectorDoc.fromJson` enforces that recursively: any prohibited key
name (`address`, `host`, `url`, `issuer`, `authority`, `origin`, `ip`, …) at any
depth — including inside nested `metadata` — and any URL-shaped string value
(`scheme://`, `http(s):`, `//host`) rejects the whole doc. A doc containing one
leak is untrusted as a whole, not sanitised per entry. Ping URLs are derived by
convention from the landscape name through a `PingUrlBuilder`, never read out of
the doc, and `HttpLandscapeSelectorSource` enforces the baked endpoint-suffix
allowlist on the doc URL **before** fetching.

The OIDC `issuer` is baked build-time config and never doc-sourced. It is a
required key in the config block, and the Doc B parser refuses an `issuer` field
outright, so it cannot leak in at runtime.

## Sign-in ordering (`SignInCoordinator`)

The C0 §13 order, in one call:

1. Resolve the home landscape from the authoritative existing-JWT claim. A
   returning user's claim decides the target; a new user picks via Doc B. The
   local cache is never consulted.
2. OIDC login, carrying the deferred-login one-time token when present.
3. Re-read the authoritative claim from the **freshly issued** JWT, so a
   server-changed or server-removed `home_landscape` overrides the pre-login
   value.
4. Run per-backend claims-first onboarding. Phases stay independent.
5. **Sign-up path only** — OnboardSync writes the claim server-side during
   onboarding, so the client confirms it from a **force-fresh** claim-bearing JWT
   (`AuthProvider.freshClaimToken` → `HomeClaimResolver.confirmedHome()`). Any
   onboarding failure, an absent forced reader, a null/blank fresh token, or a
   token without the claim all fail closed. The locally selected Doc B landscape
   is **never** persisted as if it were a claim, and the confirmed JWT value —
   which may differ from the selection — is the only value mirrored.
6. Resume the exact protected route the deeplink targeted.

`freshClaimToken()` exists because a cached read is not good enough here.
`logto_dart_sdk` v3 exposes no public force-refresh for a still-valid token, so a
just-minted 10-minute signup access token is a cache hit that would not reflect
an OnboardSync-updated claim. The guaranteed-fresh token arrives through the
injected `claimTokenRefresher` seam, and `LogtoAuthProvider` returns `null` to
fail closed when no refresher is wired.

## returnTo continuation

`ReturnTo` implements deeplink continuation: deeplink into a protected screen →
login → resume the **exact** target route with path **and** query preserved.

Only same-origin relative targets are legal. `capture` and `resolve` both reject
a scheme, an authority, a protocol-relative `//host`, and the `/\` back-slash
trick as open redirects (`urn:diene:problem:return-to`, `400`). `resolve`
re-validates on the way out, so a tampered `returnTo` value is refused rather
than followed, and `continueFrom` falls back to a caller-supplied route when the
parameter is absent or invalid.

## The engine-owned config block

The dart family has no standard-config member. Instead each engine owns its own
config block schema next to the code that reads it, and the `config` lib is the
merger/validator only: it deep-merges the YAML layers, validates the
service-composed root schema assembled from these blocks, and serves typed
slices. It never owns another lib's schema.

`AuthEngineConfig.fromBlock` parses and validates the `authEngine` block
fail-fast on the final merged layer. Required: `issuer`, `endpoint`, `appId`,
`redirectUri` (all absolute URIs, `appId` a non-empty string). Optional:
`postLogoutRedirectUri`, `scopes` (default `['openid', 'offline_access']`),
`appHandoffMount` (default `/app-handoff`, must begin with `/`), and
`endpointSuffixAllowlist` (default `['cluster.atomi.cloud']`).
`AuthEngineConfig.blockSchema` is the declarative descriptor the `config` lib
composes into the root schema, and `allowsUrl` is the use-time allowlist check —
enforced at doc level, because a doc containing one bad suffix is untrusted.

## Dependency stacking

`lib/src/contracts/result.dart` and `lib/src/contracts/problem.dart` are
**self-carried subsets** of the `diene_result` and `diene_problems` contracts,
present so this package can be built and proven in isolation in its own lane.
Their public shapes are deliberately strict subsets of the published surfaces, so
when the conductor stacks the Dart family both files are deleted and every import
is repointed at `package:diene_result/diene_result.dart` and
`package:diene_problems/diene_problems.dart` mechanically. `Result` combinator
names already track the C0 §5 cross-language table (`map` / `mapErr` / `andThen`
/ `match`).

## C0 conformance

`test/conformance/c0_conformance_test.dart` covers the auth-engine sections:
§5 (the `Problem` envelope round-trip), §7 (carrier text, the generic-expiry
problem, the fixed constants), §8 (the claim key rule, the `"true"` string rule,
the resource audience), §10 (a Doc B leaking an address is untrusted), §12 (the
lifetimes), and §13 (reading `home_landscape`). Dart is exempt from the C0 otel
config block — frontend-only; telemetry rides Faro.

**Authoritative-fixture binding is held.** The suite encodes the contract vectors
locally and does **not** claim to be backed by a versioned, source-owned C0
fixture. `contracts/c0/cases/identity.json` and its provenance excerpts under
`contracts/c0/provenance/{app-handoff,edge-docs,home-claim,onboarding-claim,token-lifetimes}.md`
are the authoritative statement of the contract; re-pointing the vectors at the
released fixture set, and recording its version and provenance, is owed work.
Creating a package-local fixture and calling it authoritative is explicitly
forbidden.

## TestHelper verdict (family TestHelper/meta tier)

**Ships: YES**, as the dependency-light sub-library
`package:diene_auth_engine/test_helper.dart` — not the escape-hatch
`diene_auth_engine_test_helper` package, because nothing here needs a test
framework.

Usefulness rationale (the family criterion): this is exactly the heavy IO and
non-determinism consumers must fake — a real IdP, per-resource token minting, a
`/User` directory over HTTP, a store install-referrer or clipboard read, a Doc B
fetch, and region pings — and `AuthExpect` removes the `Result`/phase unwrapping
every consumer test would otherwise repeat.

Contents:

- **Fakes** — `FakeAuthProvider` (scriptable sign-in/refresh/re-mint, throw
  injection, call counters, captured `lastExtraParams`), `FakeAuth` (successive
  batches modelling the force-refresh claim-repair path, with the last repeating),
  `FakeUserDirectory` (GET/POST statuses and transport-throw injection),
  `FakeAppHandoffApi`, `FakeLandscapeSelectorSource`, `FakeRegionPinger`,
  `MemoryHomeClaimStore`, `FakeInstallReferrerSource`,
  `FakeClipboardCarrierSource`.
- **Builders** — `AuthFixtures.jwt` / `registeredJwt` / `unregisteredJwt` /
  `sessionTokens` / `resourceToken` / `resourceKey`.
- **Assertions** — `AuthExpect.ok` / `err` / `errType` / `some` / `none` /
  `phase` / `status`, throwing the plain `AuthAssertionError`.

Dependency-light proof: `scripts/validate/dart-package.sh` fails if
`test_helper.dart` imports `package:test`, `package:matcher`, `package:mockito`,
or `package:mocktail`.

Meta tier: `test/meta/meta_test.dart` is measured against `lib/test_helper.dart`
only, at the single high threshold, under the `meta` codecov flag, and owes
assert-the-asserter evidence (every `AuthExpect` member shown to pass on a
known-good case and fail on a known-bad one) plus fixture/builder invariants.

## Cross-family parity with the Bun siblings

Reference: `lib/bun/auth-engine` (`@atomicloud/diene.auth-engine`) and
`lib/bun/frontend-utils` (`@atomicloud/diene.frontend-utils`). Per the dart-family
goal, an **undocumented delta is a review defect**, so every difference is listed
— including the ones that are "we do not ship this, and here is who does".

### Ported from `lib/bun/auth-engine`

| Bun surface                                                     | Dart equivalent                                                                        |
| --------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| provider interface + Logto adapter (only v1 provider)           | `AuthProvider` + `LogtoAuthProvider`                                                   |
| token cache + expiry-aware refresh + refresh-race single-flight | `AuthCoordinator` (per-`ResourceKey` cache, 30 s skew, single-flight `tokenFor`)       |
| token lifetimes: 10 min access, 14 d rotating, re-mint on open  | `TokenLifetimes` + `SessionController` (enforced, not trusted)                         |
| per-resource tokens (`resourceTree`)                            | `ResourceKey` + `IAuth.tokenFor`                                                       |
| all-tokens batch fetch (S7)                                     | `IAuth.fetchAllTokens` + `MultiBackendOnboarding`'s single registry-union acquisition  |
| multi-backend `OnboardSync`, keyed per backend                  | `BackendRegistry` + `MultiBackendOnboarding` + `OnboardingMachine` (no singleton flag) |
| claims-first detection + create-time-race GET/POST              | `Claims.hasRegistration` + the §8 state table in `OnboardingMachine.run`               |
| home-landscape claim check on every sign-in                     | `HomeClaimResolver.resolve` / `authoritativeHome` / `confirmedHome`                    |
| returnTo login-redirect + continuation helpers                  | `ReturnTo.buildLoginRedirect` / `resolve` / `continueFrom`                             |
| baked issuer, never doc-sourced                                 | `AuthEngineConfig.issuer` (required) + the Doc B parser's `issuer` refusal             |
| deferred login, one shared C0 §7 contract                       | `AppHandoffCarrier` + `DeferredLoginClient` + `HttpAppHandoffApi` (the MOBILE half)    |
| engine-owned config block schema                                | `AuthEngineConfig.blockSchema`                                                         |
| problem-typed failures on every fallible surface                | `Result` + `Problem`                                                                   |

### Deliberate deltas vs `lib/bun/auth-engine`

1. **MOBILE client only; no mint/redeem server, no web-client half.** Bun owns
   the server mint/redeem module (whose C# mirror `AtomiCloud.Diene.AuthEngine` is
   what dotnet-api hosts) and the web-side handoff initiator plus carrier builder.
   Dart ships only the **redeeming mobile client**: carrier read → `POST
{mount}/redeem` → `signIn(extraParams:)`. **Forced by the platform split** —
   the C0 §7 contract is shared, the roles are not. Consequently Dart has no
   `mintDeferredToken`, no pluggable TTL/atomic-consume store interface, and no
   redis-backed integration tier.
2. **No `pre-onboarding` selector phase enum.** Bun models the home-landscape
   resolution as a distinct `pre-onboarding` phase that runs before any backend
   phase machine. Dart expresses the same ordering structurally: the resolution is
   step 1 of `SignInCoordinator`, before `MultiBackendOnboarding.runAll()`, and is
   reported as `HomeResolutionKind` rather than as a phase value. **Deliberate** —
   both families agree it is not a per-backend state; Dart keeps `OnboardingPhase`
   to exactly the four per-backend values so a UI gate cannot accidentally observe
   a non-backend phase on a backend.
3. **No client-vs-server retriever split.** Bun ships two retriever
   implementations behind one interface (browser context vs server/edge context).
   Dart has exactly one context — the app process — so `AuthCoordinator` is the
   single `IAuth` implementation. **Forced by the runtime shape.**
4. **`Result<T>` with a fixed `Problem` error channel**, not Bun's
   `Result<T, E>`. **Forced by the family Result contract** (the same delta
   `diene_interfaces` records).
5. **`freshClaimToken()` is an explicit injected seam.** Bun's JWT stack can force
   a token refresh directly; `logto_dart_sdk` v3 exposes no public
   force-refresh/cache-invalidation for a still-valid token, so the guaranteed-fresh
   claim read arrives through the injected `claimTokenRefresher` and returns `null`
   to fail closed when it is not wired. **Forced by the SDK**, and the
   fail-closed behaviour is the family-visible contract.
6. **Refresh bookkeeping is synthesized in the Logto adapter.** The Logto SDK owns
   rotation and reuse detection internally and never surfaces the refresh token, so
   `LogtoAuthProvider` synthesizes the family `SessionTokens` refresh fields. The
   rotating-reuse guarantee `SessionController` enforces is proven through provider
   fakes and applies verbatim to any provider that does surface refresh tokens.
   **Forced by the SDK.**
7. **No JWKS policy surface.** Neither family mandates a minimum JWKS lifetime or
   retry floor (Q-I35 accepted the library defaults); Dart additionally does no
   signature verification client-side at all — `Claims` reads the payload to decide
   routing and gating, and verification stays a provider/JWKS concern. **Parity by
   omission, stated because a reader could expect a verifier here.**
8. **No FGA and no server-side guard surface.** Dart/Flutter is client-side only,
   so the family nullable-userId ownership pattern has no dart implementation.
   **Forced by the family shape** (the dart-family goal says so explicitly).

### Deltas vs `lib/bun/frontend-utils`

Dart has no `frontend-utils` member. The bun lib's responsibilities therefore
split three ways: some land here, some in `lib/dart/api-engine`, and some in
`flutter-base`. Each is named.

#### Doc B landscape-selector client vs the bun edge-doc client

Bun's `/discovery` subpath ships **one** edge-doc client covering all three docs:
Doc A (constantly refreshed fleet doc), Doc B (sign-up landscape selector), and
Doc C (dormant platform catalog), plus the Problem-catalog fetch off the same
hosts, plus the dormant rescue router.

Dart splits that client by lifecycle, and this package owns **only the Doc B
half**:

| Bun `/discovery` concern                                                                | Dart owner                                                                                               |
| --------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| Doc B fetch + ping-and-pick-home                                                        | **HERE** — `LandscapeSelectorClient`, sign-up only                                                       |
| endpoint-suffix allowlist on a doc URL                                                  | **HERE** for Doc B — `AuthEngineConfig.allowsUrl` + `HttpLandscapeSelectorSource`                        |
| baked issuer, never doc-sourced                                                         | **HERE** — required config key + parser refusal                                                          |
| home assignment handed to the auth flow                                                 | **HERE** — `HomeClaimResolver` → `SignInCoordinator`                                                     |
| Doc A fleet doc (`catalogHosts[]`, constant refresh)                                    | `lib/dart/api-engine`                                                                                    |
| Doc C platform catalog (dormant, ordered candidates)                                    | `lib/dart/api-engine`                                                                                    |
| dormant rescue router (disk cache, baked seeds, jittered budgeted scan, pin-until-heal) | `lib/dart/api-engine` (the dart twin lives there because dart has no frontend-utils lib)                 |
| per-service Problem-catalog fetch                                                       | `lib/dart/problems` (catalog shape) + `flutter-base` (the classifier/visualizer consuming the edge copy) |

**Deliberate delta, and the reason is lifecycle, not convenience.** Doc B is a
once-per-user sign-up-time fetch whose output is an identity fact (the home
claim), so it belongs with the code that writes and confirms that claim. Doc A and
Doc C are a constantly-refreshed carrier and a dormant failure-path catalog whose
output is an address, so they belong with the HTTP client. Bun can keep them
together because `frontend-utils` is a grab-bag of frontend machinery; dart has no
such member, so the split is by owner rather than by subpath.

Two behavioural notes a cross-language reader needs:

- Bun's allowlist rejection is documented per-URL in its features table; the C0
  §10 normative rule and this package are **doc-level** — a doc containing one bad
  suffix is untrusted as a whole. `LandscapeSelectorDoc.fromJson` throws for the
  whole doc, and `HttpLandscapeSelectorSource` refuses the fetch outright.
- **Monotonic per-doc version enforcement is NOT implemented here.** C0 §10
  requires clients never to accept a doc version older than one already seen, and
  Bun proves it per doc (A/B/C). Doc B in this package is fetched exactly once per
  user at sign-up, so there is no previously-seen version to compare against
  within its lifecycle, and `LandscapeSelectorDoc` carries no `version` field.
  **This is an open delta, not a forced one**: if a re-pick or re-home flow ever
  re-fetches Doc B, version monotonicity must be added here. `lib/dart/api-engine`
  owes the enforcement for Doc A and Doc C, where the docs genuinely are refetched.

#### All five UX-pattern mechanism-hook twins

Bun's `frontend-utils` ships five mechanism-only subpaths. The dart-family goal
requires each twin to be accounted for. **This package ships none of them** — they
are UI mechanisms, and this is the auth engine — but every one has a named owner
and a stated flutter idiom, because an unaccounted twin is a review-red.

| #   | Bun subpath    | Mechanism                                                                                                                                                      | Flutter idiom (the twin)                                                                                                                                                     | Ships here? | Owner                                                                   |
| --- | -------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------- | ----------------------------------------------------------------------- |
| 1   | `/persistence` | localStorage-backed form drafts, cleared on the four triggers (cancel/close/submit/reset), restore-offer on accidental dismissal (backdrop tap / back gesture) | `SharedPreferences`/Hive-backed drafts behind the same clear-trigger set; the accidental-dismissal restore offer maps to `PopScope` / barrier-dismiss interception           | **No**      | `flutter-base` (form-persistence widget)                                |
| 2   | `/loader`      | ~100 ms debounce for CONTENT loaders only; button spinners never debounced                                                                                     | the same ~100 ms content-only debounce in front of the loading branch; async-button spinners stay immediate                                                                  | **No**      | `flutter-base` (async button + error/loading tiers)                     |
| 3   | `/urlstate`    | real-time URL↔state sync: server-reads-on-load (`searchParams`), client-updates-on-interaction via debounced `replaceState`, never pushState-per-keystroke     | route/query-param state via **`go_router`**: read on route build, update with a debounced `replace` (not `push`) so back/forward stay correct                                | **No**      | `flutter-base` (go_router route-for-every-screen + deeplink map)        |
| 4   | `/toast`       | passive-only, ≥5 s dwell, `aria-live` wired; never used for an error                                                                                           | the same passive-only, ≥5 s dwell rule, with the live-region announcement made through **`SemanticsService.announce`** (the `aria-live` twin)                                | **No**      | `flutter-base`                                                          |
| 5   | `/a11y`        | `env(safe-area-inset-*)` exposed to consumers; `prefers-reduced-motion` exposed plus an animation-disable helper                                               | `MediaQuery.viewPadding` (and `padding`) as the safe-area-inset twin; `MediaQuery.disableAnimations` / the platform reduced-motion flag as the `prefers-reduced-motion` twin | **No**      | `flutter-base` (safe-area layout, reduced-motion-respecting animations) |

**Why `flutter-base` and not this lib, for all five.** Each is a **widget-tree**
mechanism: it needs a `BuildContext`, an `InheritedWidget`/`MediaQuery` lookup, a
router, or a `SharedPreferences`-class platform store. Bun can ship them as
framework-free core plus a thin React binding because its core logic is genuinely
React-free; the flutter twins have no equivalent framework-free core — `MediaQuery`
and `go_router` **are** the mechanism. Putting them in an auth library would give
this package a UI surface it has no other reason to have, and would make every
consumer of the auth engine depend on a router. The dart-family goal already
assigns the corresponding deliverables to `flutter-base` (its six
product-thoughtfulness deliverables and its widget list name form-persistence
with clear/restore triggers, safe-area layout, reduced-motion animations, and
go_router route/query-param state explicitly).

**One boundary that does touch this package.** `flutter-base`'s returnTo
login-redirect-return for deeplinks into protected screens consumes `ReturnTo`
from here — the **route continuation** is auth (it survives a login round trip), the
**query-param-as-state** mechanism is UI. The split is: this package validates and
round-trips the target; `go_router` navigates to it.

### The Flutter-dependency delta (family precedent)

State it plainly: **unlike the four pure-Dart siblings — `diene_result`,
`diene_interfaces`, `diene_core_utils`, `diene_problems` — this package depends on
the Flutter SDK.** `pubspec.yaml` declares `environment.flutter: '>=3.24.0'` and
`dependencies.flutter: {sdk: flutter}`.

That is **forced, not stylistic**, on three independent grounds:

1. `logto_dart_sdk` 3.0.0 itself declares `environment.flutter: '>=1.17.0'` and
   pulls `flutter_secure_storage` and `flutter_web_auth_2`. A package that binds
   Logto cannot be pure Dart.
2. The deferred-login carrier read needs real platform access — `Clipboard` on
   iOS, the Install Referrer on Android. `ClipboardCarrierReader` imports
   `package:flutter/services.dart`. (`CallbackInstallReferrerSource` deliberately
   takes injected callbacks so the `android_play_install_referrer` plugin stays in
   the app rather than here — the platform-plugin surface is kept as small as the
   contract allows, but it is not zero.)
3. The dart-family goal names neon `auth/auth_service.dart` (logto_dart_sdk) as
   **both** this lib's seed **and** its `flutter-base` deletion target. For the E4
   swap-in to delete the in-app copy, the Logto binding must live **here**. Moving
   it out to keep this package pure Dart would leave the deletion target with
   nowhere to go and break the dogfood DoD line.

`SessionController` additionally extends `ChangeNotifier` (from
`package:flutter/foundation.dart`), which is the idiomatic notification seam a
Flutter consumer gates UI on.

**Two `dev_dependencies` consequences follow, and both are recorded in
`pubspec.yaml`'s own comments:**

- **No `test:` dev_dependency.** `flutter_test` from the SDK pins `test_api` to
  0.7.11 while `test >=1.31.2` requires `test_api` 0.7.13, so declaring both makes
  version solving fail outright ("test >=1.31.2 is incompatible with flutter_test
  from sdk"). `flutter_test` re-exports the `test` framework, so every tier — unit,
  conformance, meta — still runs on the same matchers; nothing is lost, and
  `flutter test` is the runner.
- **No `pana:` dev_dependency.** Same root cause. A Dart pub **workspace** shares
  ONE resolution across every member, so a pana dev_dep is solved against
  `flutter_test`'s SDK pins: pana >=0.23.13 needs analyzer ^13 and test ^1.26.2
  while `flutter_test` pins matcher 0.12.19 + test_api 0.7.11, and the solver
  reports "pana >=0.23.13 is incompatible with flutter_test from sdk". Moving it to
  the workspace **root** manifest does not help — same shared resolution. pana is
  therefore installed into its own isolated resolution
  (`dart pub global activate pana`) and invoked as `dart pub global run pana`,
  which is exactly how pub.dev itself runs it; the pana-score gate keeps its
  `--exit-code-threshold 0` assertion unchanged.

**Family precedent.** The lead has ruled this documented delta the family
precedent for Flutter-dependent members. `lib/dart/api-engine` is expected to
follow it — same reasoning, same two dev_dependency consequences, same recorded
justification — or to justify a difference **against** this note rather than
deciding independently. A Flutter dependency added without this record is the
review-red; a Flutter dependency with it is a documented delta.

Wire-level `Result` and `Problem` equivalence stays owned by `diene_result` and
`diene_problems`. This package duplicates neither codec — it carries a temporary
subset only while it is built in isolation (see "Dependency stacking").
