---
name: diene-dotnet-auth-engine-usage
description: Use AtomiCloud.Diene.AuthEngine and its TestHelper in .NET services. Use when validating tokens, enforcing scope or landscape policy, acquiring service credentials, revoking sessions, enabling deferred app handoff, managing Logto users, or faking these seams in tests.
---

# Diene .NET Auth Engine usage

Both directions of a Logto-compatible auth boundary. Server-side: validate a
token, then apply policy. Client-side: acquire and renew credentials. Everything
returns `Result<T, IDomainProblem>` — no method on this surface throws to report
a failed authentication or authorization.

## Enable the module; never hand-host the endpoints

```csharp
builder.Services.AddSingleton<IDeferredTokenStore>(persistentDeferredStore);
builder.Services.AddAtomiAuthEngine(config);
app.MapAtomiAuthEngine(config);
```

`AddAtomiAuthEngine` registers the clock and key resolver with `TryAdd`, so a
test host that already supplied a fixed clock keeps it. Do not re-register
`IAuthClock` after calling it expecting an override — supply yours first.

The engine deliberately does **not** register an `IDeferredTokenStore`.
Production must supply a persistent implementation whose `Consume` operation
atomically claims one active nonce and whose `Settle` operation makes consumed
or revoked state terminal. An in-memory cache is not a production substitute:
handoffs must survive a service restart.

Add `AppHandoffExpired` to the Problems catalog with
`AddAtomiAuthEngineProblems(config)` and enable the Problems exception handler.
Do not hand-render a redeem error; every invalid path intentionally collapses
to the same RFC 9457 `410` response with `Cache-Control: no-store`.

## Keep deferred handoff single-use and non-oracular

`MapAtomiAuthEngine(config)` maps exactly:

- `POST {mount}` — authenticated mint from an empty JSON object
- `POST {mount}/redeem` — unauthenticated nonce exchange
- `GET {mount}/session` — validated session projection

The mint route returns a 32-random-byte, 43-character base64url nonce with a
fixed 15-minute expiry. Store only the lowercase SHA-256 digest passed to
`IDeferredTokenStore`; never persist or log the raw nonce.

Redeem claims the record before any provider call, makes one
`GET /api/users/{sub}`, and refuses deleted, suspended, or email-rebound users.
The email comparison folds ASCII case only. The Logto token is minted after the
identity check with fixed `expiresIn: 120`, then the claim is settled consumed.
Any later failure revokes it best-effort; if settlement or the process crashes,
the exclusive claimed state remains and replay still fails closed.

The v1 redeem body is strict and case-sensitive:

```json
{
  "nonce": "43-character-base64url-value",
  "device": {
    "platform": "android",
    "appVersion": "1.2.3",
    "osVersion": "16",
    "model": "example-device"
  }
}
```

Only `android` and `ios` are valid platforms. Unknown top-level or device keys
are rejected. Never return a different problem for malformed, unknown, expired,
replayed, deleted, suspended, rebound, store-failed, or provider-failed input;
doing so creates an account-state oracle.

## Bake the issuer; never read it from discovery

Pass the OIDC issuer as configuration. The validator compares against that value
directly and takes only the signing keys from the discovery document. Do not
"simplify" this by reading `issuer` out of the discovery response: that hands
issuer selection to whoever controls the endpoint.

Build config through the `Create` factories and check the failure. They return
the offending field by name:

```csharp
var config = AuthEngineConfig.Create(logto, handoff, TokenLifetimeConfig.Default, "home_landscape");
if (config.IsFailure(out var error)) throw new InvalidOperationException(error.ToString());
```

Never construct configuration by bypassing the factories. Validation is where a
non-canonical endpoint or a traversal-carrying mount path gets rejected.

## Guard requests with composed policies

```csharp
var outcome = await guard.GuardAsync(
    token,
    audience,
    [new RequireAllScopes("notes:read"), new RequireHomeLandscape(config, landscape)]);
```

Policies evaluate in order and stop at the first refusal. Put the cheapest and
most specific first so the reported problem is the most actionable one.

`GuardOrAnyAsync` is the any-of-these-scopes shorthand.

**Do not pass an empty accepted set to `RequireAnyScope` expecting it to admit.**
It refuses, deliberately: "any of nothing" is unsatisfiable and admitting would
make a misconfigured policy an open door.

## Route the two refusal types differently

`Unauthenticated` means no identity was established — respond 401 and let the
client re-authenticate. `Unauthorized` means an established identity lacks a
permission — respond 403; re-authenticating will not help.

Within those, do not collapse:

- **expired** vs **not yet valid** — the second is resolved by waiting, and
  treating it as expired sends the client into a refresh loop that cannot win
- **absent** vs **mismatched** home landscape — only the first is resolved by
  onboarding

Render failures through the published Problems pipeline with
`problem.ToException()`. Do not build your own `ProblemDetails` for these; the
Problems package's registered handler already emits RFC 9457 correctly.

## Let the cache own token lifetime

```csharp
var token = await cache.GetAsync(resource, scopes);
```

Ask for a token per use. Do not cache the returned `TokenResponse` yourself or
compare expiry by hand — `TokenCache` renews inside the skew so a token never
expires mid-flight, and it collapses a concurrent burst into one acquisition.

**Call `Clear()` after revoking a user's sessions.** Otherwise a revoked session
keeps being served from cache until its tokens age out.

On refresh, **store the returned refresh token in place of the one you
presented.** Rotation is what lets the IdP detect a stolen token; keeping both
defeats it.

## Test with the shipped fakes, not a live IdP

```csharp
using var issuer = new TestTokenIssuer("https://logto.example.com/oidc");
var clock = new FakeAuthClock(now);
var validator = new JwtTokenValidator(config, issuer.KeyResolver, clock);

var token = issuer.MintValidFor("user-1", audience, now, TimeSpan.FromMinutes(10), ["notes:read"]);

(await validator.ValidateAsync(token, audience))
    .ShouldBeAuthorized()
    .ShouldHaveSubject("user-1")
    .ShouldGrantScopes("notes:read");
```

- `TestTokenIssuer` mints **genuinely signed** JWTs. Do not hand-assemble token
  strings instead: a validator with its signature check disabled would pass a
  suite built on fake strings, which is precisely the defect the check exists to
  catch. Use `SigningCredentials` when you need a token `Mint` refuses to make.
- `FakeAuthClock.Advance` exercises expiry instantly. Never `Thread.Sleep` for a
  lifetime test.
- `FakeCredentialClient` scripts responses in order and **counts calls** — assert
  `AcquireCount` to prove a second read was served from cache.
- `FakeOnboardingBackend` writing a landscape also marks the subject known,
  mirroring the real backend after `OnboardSync`.
- `StubHttpMessageHandler` **throws on an unexpected extra request** rather than
  returning a default, so a stray call cannot pass unnoticed.
- `InMemoryDeferredTokenStore` implements the real atomic claim and terminal
  settlement rules. Use its `Records` snapshots to assert digest-only storage,
  TTL, and replay state; do not use it as a production store.
- `FakeAuthManagement` scripts user lookup and token-mint failures, records the
  one lookup/email-mint sequence, and exposes claim, role, and deletion state.
  Seed the current redeem-time identity with `SetUser`.

For concurrency tests, launch several `Exchange` calls against one handoff and
assert exactly one succeeds. A sequential double-call does not prove `Consume`
is atomic.

## Onboarding is claims-first

Call `ResolvePhaseAsync` and branch on the phase. It reads the claim before
touching the backend, so an onboarded user costs no round trip. After
`CompleteAsync` the phase stays `AwaitingSync` until a **fresh token** carries
the new claim — do not treat the write as making the caller `Complete`, because
the next request's token would disagree.

## Reuse, do not rebuild

Wire formats, JSON options, and slug or key normalization come from
`AtomiCloud.Diene.CoreUtils`. Problem types come from
`AtomiCloud.Diene.Problems`. Do not re-derive any of them here.
