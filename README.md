# Diene .NET Auth Engine

<!-- ### nix-root -->
<!-- #### source: main -->

Diene's reproducible development environment is managed by Nix. Run `direnv allow` once, then use `pls` tasks from the loaded shell.

<!-- ### workspace -->
<!-- #### source: workspace -->

This branch is the workspace baseline inherited by every downstream sample: split CI/CD, secrets, release configuration, validators, standards, and vendored agent-skill synchronization.

## Commands

- `pls setup` — synchronize installed diene package skills.
- `pls lint` — run every pre-commit gate.
- `pls secret:scan` — scan tracked content for secrets.
- `pls skills:sync` — rebuild `.claude/skills/vendor/` from installed packages.

## Standards

- [CI/CD workflows](docs/standards/ci-cd/index.md)
- [conventional commits](docs/standards/conventional-commits/index.md)
- [Infisical and secrets](docs/standards/infisical/index.md)
- [linting and pre-commit](docs/standards/linting/index.md)
- [Nix flakes and development shells](docs/standards/nix/index.md)
- [release automation](docs/standards/semantic-release/index.md)
- [service-tree identity](docs/standards/service-tree/index.md)
- [shell scripts](docs/standards/shell-scripts/index.md)
- [Taskfile conventions](docs/standards/taskfile/index.md)

<!-- ### shared -->
<!-- #### source: shared -->

## Shared standards

- [Authorization](docs/standards/authorization/index.md)
- [Contributor documentation](docs/standards/contributor-docs/index.md)
- [Date and time](docs/standards/datetime/index.md)
- [Domain-driven design](docs/standards/domain-driven-design/index.md)
- [Functional practices](docs/standards/functional-practices/index.md)
- [Software design philosophy](docs/standards/software-design-philosophy/index.md)
- [SOLID principles](docs/standards/solid-principles/index.md)
- [Stateless OOP and dependency injection](docs/standards/stateless-oop-di/index.md)
- [Testing](docs/standards/testing/index.md)
- [Three-layer architecture](docs/standards/three-layer-architecture/index.md)
- [Utility libraries](docs/standards/utilities/index.md)
- [Data validation](docs/standards/validation/index.md)

Domain-specific documentation belongs under [docs/domain/](docs/domain/README.md).
The `docs/standards/contracts/` location is reserved for the separately owned C0
contracts standard.

<!-- ### dotnet-base -->
<!-- #### source: dotnet-base -->

## .NET 10 foundation

[![CI](https://github.com/AtomiCloud/diene.dotnet-auth-engine/actions/workflows/ci.yaml/badge.svg)](https://github.com/AtomiCloud/diene.dotnet-auth-engine/actions/workflows/ci.yaml)
[![Unit coverage](https://codecov.io/gh/AtomiCloud/diene.dotnet-auth-engine/graph/badge.svg?flag=unit)](https://codecov.io/gh/AtomiCloud/diene.dotnet-auth-engine)
[![Integration coverage](https://codecov.io/gh/AtomiCloud/diene.dotnet-auth-engine/graph/badge.svg?flag=int)](https://codecov.io/gh/AtomiCloud/diene.dotnet-auth-engine)
[![Commit activity](https://img.shields.io/github/commit-activity/m/AtomiCloud/diene.dotnet-auth-engine)](https://github.com/AtomiCloud/diene.dotnet-auth-engine/commits/main)

This branch adds the .NET 10 toolchain, the `App`/`Lib`/`UnitTest`/`IntTest`
sample, merged multi-project coverage, strict and LLM dead-code modes. See [the .NET baseline](docs/developer/dotnet-baseline.md).

Common commands:

- `pls build`, `pls dev`, `pls run`, and `pls preview`
- `pls test`, `pls test:unit`, `pls test:int`, and the coverage variants
- `pls deadcode` for the non-blocking review; CI owns strict dn-inspect

The auth contract is documented in [docs/domain/auth-engine.md](docs/domain/auth-engine.md).
Production observability is intentionally absent until the observability add-back.

<!-- ### dotnet-lib -->
<!-- #### source: dotnet-lib -->

## Auth engine packages

[![NuGet version](https://img.shields.io/nuget/v/AtomiCloud.Diene.AuthEngine)](https://www.nuget.org/packages/AtomiCloud.Diene.AuthEngine)
[![NuGet downloads](https://img.shields.io/nuget/dt/AtomiCloud.Diene.AuthEngine)](https://www.nuget.org/packages/AtomiCloud.Diene.AuthEngine)
[![Meta coverage](https://codecov.io/gh/AtomiCloud/diene.dotnet-auth-engine/graph/badge.svg?flag=meta)](https://codecov.io/gh/AtomiCloud/diene.dotnet-auth-engine)

`AtomiCloud.Diene.AuthEngine` covers both directions of a Logto-compatible auth
boundary: server-side token validation with scope and home-landscape policies,
and client-side credential acquisition with rotating refresh and session
revocation. It also ships the deferred app-handoff mint/redeem module and the
full Logto management seam. `AtomiCloud.Diene.AuthEngine.TestHelper` provides
the identity-provider, token, management, deferred-store, and per-backend
onboarding fakes consumers must stand in for.

```bash
dotnet add package AtomiCloud.Diene.AuthEngine
dotnet add package AtomiCloud.Diene.AuthEngine.TestHelper
```

### Enable the module

The engine is enable-able, not implicit. Register it once and map its endpoints
under the configured mount:

```csharp
using AtomiCloud.Diene.AuthEngine;
using AtomiCloud.Diene.AuthEngine.Config;
using AtomiCloud.Diene.AuthEngine.Module;

var management = LogtoManagementConfig
    .Create("https://logto.example.com", "https://default.logto.app/api", clientId, clientSecret)
    .Get();

var logto = LogtoConfig
    .Create("https://logto.example.com", BuildTimeIssuer, appId, appSecret, management)
    .Get();

var config = AuthEngineConfig
    .Create(logto, HandoffConfig.Default, TokenLifetimeConfig.Default, "home_landscape")
    .Get();

// The library deliberately installs no production store. This implementation
// must be persistent and Consume must claim one nonce atomically.
builder.Services.AddSingleton<IDeferredTokenStore>(persistentDeferredStore);
builder.Services.AddAtomiAuthEngine(config);

var app = builder.Build();
app.MapAtomiAuthEngine(config);
```

The OIDC issuer is baked in at build time and compared against directly, so a
compromised discovery document cannot move trust to another issuer. Only the
signing keys come from discovery.

Register `AppHandoffExpired` with the Problems pipeline through
`AddAtomiAuthEngineProblems(config)` and enable its exception handler. Every
malformed, missing, expired, replayed, rebound, deleted, suspended, or
upstream-failed redeem then produces the same RFC 9457 `410` response without
revealing account state.

### Use deferred app handoff

One `MapAtomiAuthEngine(config)` call exposes exactly three routes beneath the
configured mount:

| Route                 | Contract                                                                                                    |
| --------------------- | ----------------------------------------------------------------------------------------------------------- |
| `POST {mount}`        | Authenticated empty JSON object; returns a 43-character nonce and its 15-minute expiry.                     |
| `POST {mount}/redeem` | Strict `{nonce, device}` JSON; returns the Logto one-time token, current email, and fixed `expiresIn: 120`. |
| `GET {mount}/session` | Returns the validated bearer-token session view.                                                            |

The store receives only the lowercase SHA-256 digest, never the raw nonce.
`Consume` must perform one atomic `Active` → `Claimed` transition, and `Settle`
must make `Consumed` and `Revoked` terminal. Redeem re-resolves the stored OIDC
subject once, refuses a missing/suspended/email-rebound user, and mints the
provider token only after that check. A claimed record is never made active
again, including after a process crash or provider failure.

The redeem request is case-sensitive and rejects unknown top-level or device
keys. Its device object requires `platform` (`android` or `ios`) and may carry
`appVersion`, `osVersion`, and `model` telemetry.

### Guard a request

```csharp
var outcome = await guard.GuardAsync(
    bearerToken,
    "https://api.example.com",
    [new RequireAllScopes("notes:read"), new RequireHomeLandscape(config, "lapras")]);

return outcome.Match(
    claims => Results.Ok(claims.Subject),
    problem => throw problem.ToException());
```

Refusals are the published `Unauthenticated` and `Unauthorized` catalog problems.
The distinction is load-bearing: the first means the caller has no established
identity and should sign in, the second means an established identity lacks a
permission. An absent home-landscape claim is reported separately from a
mismatched one, because only the former is resolved by onboarding.

### Acquire a service token

```csharp
var cache = new TokenCache(credentialClient, clock, config.Lifetimes);
var token = await cache.GetAsync("https://api.example.com", ["notes:read"]);
```

Tokens renew inside the expiry skew rather than after expiry, so a request never
carries a token that dies in flight. Lifetimes default to alcohol parity:
10-minute access tokens and 14-day rotating refresh tokens.

### Test against the fakes

```csharp
using var issuer = new TestTokenIssuer("https://logto.example.com/oidc");
var clock = new FakeAuthClock(now);
var validator = new JwtTokenValidator(config, issuer.KeyResolver, clock);

var token = issuer.MintValidFor("user-1", "https://api.example.com", now, TimeSpan.FromMinutes(10), ["notes:read"]);

(await validator.ValidateAsync(token, "https://api.example.com"))
    .ShouldBeAuthorized()
    .ShouldGrantScopes("notes:read");
```

`TestTokenIssuer` mints genuinely signed JWTs rather than hand-assembled strings,
so a validator with its signature check disabled cannot pass a suite built on it.
Advance `FakeAuthClock` to exercise expiry without waiting.

The TestHelper also provides a genuinely atomic deferred-store fake and a
stateful management fake:

```csharp
var store = new InMemoryDeferredTokenStore(clock);
var management = new FakeAuthManagement();
management.SetUser(new AuthManagementUser("user-1", "owner@example.test", false));

var minter = new DeferredTokenMinter(store, management, clock);
var handoff = (await minter.Mint(
    new DeferredPayload("user-1", "owner@example.test"))).Get();
var exchange = (await minter.Exchange(handoff.Nonce)).Get();
```

Run `nix develop .#ci -c ./scripts/ci/pkg-validate.sh` to pack both packages,
positive-control their managed public surfaces, prove one mapping call exposes
all three routes, validate metadata and symbols, and restore them into a scratch
consumer. See [the library baseline](docs/developer/dotnet-lib-baseline.md) for
release and promotion guidance.
