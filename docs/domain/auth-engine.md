---
title: Auth engine contract
description: The token, policy, and onboarding contract shipped by AtomiCloud.Diene.AuthEngine.
---

# Auth engine contract

The auth engine is a Logto-compatible boundary covering both directions of a
service's authentication surface. Server-side it validates tokens and applies
policy; client-side it acquires and renews credentials. Both halves return
problem-typed failures rather than throwing, so they compose into a `Result`
pipeline without a caller wrapping them in a `try`/`catch` to stay total.

## Trust is anchored at build time

The OIDC issuer is a configuration value baked in at build time and compared
against directly. Only the signing keys are read from the issuer's discovery
document. A compromised or substituted discovery endpoint can therefore cause a
validation failure, but it cannot move trust to a different issuer.

`LogtoConfig.Create` refuses anything that is not a canonical origin — no
credentials, path, query, or fragment — so a misconfigured endpoint fails at
composition with the offending field named, rather than at the first request.

## Two refusals that must not be conflated

| Problem           | Meaning                                    | Caller's remedy           |
| ----------------- | ------------------------------------------ | ------------------------- |
| `Unauthenticated` | No identity could be established           | Sign in, or fix the token |
| `Unauthorized`    | An established identity lacks a permission | Request access            |

The engine reports several distinct causes within those two types, and the
distinctions are deliberate:

- **Expired** and **not yet valid** are separate. The remedy for the first is to
  re-authenticate; for the second it is to wait. Reporting a not-yet-valid token
  as expired sends a client into a refresh loop that cannot succeed.
- **Absent** and **mismatched** home-landscape claims are separate. An absent
  claim means onboarding has not written it and the phase machine resolves it; a
  mismatch means the user belongs to another landscape and no amount of
  onboarding will change that.
- **Unreachable identity provider** is reported as an authentication failure, not
  as a success with no claims. A caller that cannot reach the IdP fails closed.

## Policies compose and fail closed

Policies are applied in order and evaluation stops at the first refusal, so the
reported problem describes the first thing actually wrong rather than an
arbitrary one.

`RequireAnyScope` over an empty accepted set **refuses**. "Any of nothing" is not
satisfiable, and admitting it would turn a misconfigured policy into an open
door — the failure direction that costs the most.

## Token lifecycle

Lifetimes follow alcohol parity and are the contract, not an implementation
detail:

- access tokens live **10 minutes**
- refresh tokens live **14 days** and **rotate** — each refresh issues a new one,
  so replaying a retired token is what lets the IdP detect theft
- apps **re-mint on open**, so a fresh session always starts with a fresh token
- `revokeUserSessions` clears sessions through the Logto Management API

`TokenCache` renews _inside_ the expiry skew rather than after expiry, so a
request never carries a token that dies in flight. Concurrent callers collapse
into a single acquisition. Clearing the cache after a revocation is required:
otherwise a revoked session keeps being served from cache until its tokens age
out naturally.

Every expiry decision reads the instant through `IAuthClock`. No wall clock is
consulted implicitly, which is what makes lifetime behaviour testable without
waiting.

## Onboarding is claims-first

`OnboardingCoordinator` consults the home-landscape claim on the validated token
**before** asking any backend. A present claim means the user is onboarded and no
backend round trip is owed, so the common path costs nothing.

When the claim is absent, the backend distinguishes two states:

- no user record → `SelectLandscape`, the user has not chosen yet
- a user record → `AwaitingSync`, the pick landed but the claim has not

Collapsing those would re-show the landscape selector to a user who already
chose. Note that completing onboarding does not immediately yield `Complete`:
the claim lives in the token, so the caller stays at `AwaitingSync` until a fresh
token carries it. Reporting `Complete` off the backend write would contradict
what the next request's token actually says.

## Wire formats

Instants are ISO 8601 / RFC 3339 in UTC, per the C0 serialization contract, and
the shipped surface reuses `AtomiCloud.Diene.CoreUtils` codecs rather than
re-deriving them.
