---
name: diene-go-auth-engine-usage
description: Use the diene Go auth-engine — token validation, the ownership guard, per-resource tokens, deferred login, OnboardSync, and its TestHelper.
---

# Diene Go auth-engine usage

`github.com/AtomiCloud/diene.go-auth-engine` is the Go family's server-side auth
engine. It ships decisions, not an HTTP framework: wire its results into your own
handlers. Every fallible call returns `(T, error)` where the error carries an RFC
9457 `problem.Problem`; recover it with
`var pe *problem.Error; errors.As(err, &pe)`.

Start with the compiling examples in `lib/authengine/example_test.go`,
`lib/deferred/example_test.go`, and `lib/onboard/example_test.go`.

## Validation

Build one `authengine.Validator` per issuer at startup. **The OIDC issuer is
baked build-time config — never source it from a document.** Feed the validator a
`VerificationKeys`; use `logto.NewRemoteJWKS` in production and the TestHelper
fake IdP in tests. Validate the access token with `Validate`; validate a body ID
token with `ValidateIDToken` (audience is deliberately skipped). Use
`ExtractOnboarding` for the onboarding create path — it fully validates both
tokens and proves they share one `sub`.

## Authorization — nullable-userId ownership

Do: take a `*string` userId alongside the resource id, guard FIRST, then filter
rows by owner IFF the pointer is non-nil.

- `guard.Sub(principal, target)` — owner only.
- `guard.SubOrAny(principal, target, authengine.ClaimRoles, "admin")` — owner or
  any listed role. Admin/system callers pass `nil`.
- `guard.SubOrAll(...)` — stricter writes.
- `guard.Registered(principal, "alcohol-zinc")` — the registration-claim policy,
  wired as a real default on owned-resource paths.

Don't: default a nil userId from `sub` server-side (it kills the admin path);
call the service before the guard (it turns "nil userId" into "unfiltered data
for anyone"); take caller identity from a body/header field; or turn an
owner-mismatch row miss into a 403 (that leaks existence — return not-found).
There is no FGA/policy engine here and none is coming.

## Per-resource tokens

Declare backends once in a `ResourceTree`, then resolve through a `TokenCache`
(single-flight, expiry-aware, KV-backed through the `TokenStore` seam). Use
`All` at onboarding to batch every resource eagerly — not lazy-on-first-call.
`NewSessionSource` mints for a user session; `NewClientCredentialsSource` mints
machine-to-machine tokens (the operator's flow).

Lifetimes are contract constants, not knobs: access 10 minutes, refresh 14 days
rotating with reuse detection (`Rotator`), and re-mint on open. The deferred
one-time token's 120 seconds is a different thing entirely — never conflate them.

## Deferred deep-link login

`deferred.Minter.Mint` issues a one-time 15-minute nonce bound to a session;
`Exchange` consumes it exactly once and mints the IdP one-time token. Replay or
expiry is a typed Problem. Back the `Store` seam with your KV. Build the store
carrier with `deferred.AndroidReferrer` / `deferred.ClipboardPayload`.

## OnboardSync

Claims-first, keyed per backend — there is no singleton onboarded flag.
`onboard.Sync.Run` inspects each backend's `<platform>_<service>` claim; only for
an ABSENT claim does it probe `Me` and create on 404 (a 409 is success). Claim
write-back then a forced token refresh and re-verify follow. A stale claim is not
a second detector: it takes the normal 401/404 path. Check the home-landscape
claim on EVERY sign-in/sign-up; when absent, run the pre-onboarding selector
(`onboard.Selector`) before any backend phase machine.

## TestHelper

Import `<module>/testhelper` rather than rebuilding fakes: `NewFakeIdP` (real
RSA signing, scriptable failures, `Validator`/`Guard` constructors),
`NewFakeProvider`, `NewMemoryTokenStore`, `NewMemoryDeferredStore`,
`NewFakeBackend`, and the `AssertProblem`-style auth assertions. Never add
`export_test.go` or a white-box shim; new helper behavior needs black-box meta
tests and targeted meta coverage.

Before changing an exported API run `./scripts/ci/pkg-validate.sh all`. Keep v1
changes backward compatible; an intentional breaking release needs a reviewed
`/v2` module-path migration.
