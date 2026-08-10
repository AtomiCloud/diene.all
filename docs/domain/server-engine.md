---
id: server-engine
title: Server engine
---

# Server engine

`AtomiCloud.Diene.ServerEngine` owns the MVC server wiring every Diene .NET
service shares. It is a separate package from `AtomiCloud.Diene.Problems` on
purpose: the Problems package owns the problem contract and its terminal ASP.NET
adapter, and no server wiring leaks into it.

## The one error shape

`AtomiController` turns a `Result<T, IDomainProblem>` into an action result and
raises failures as `DomainProblemException`. The shipped
`DomainProblemExceptionFilter` catches them inside the MVC pipeline and writes
one RFC 9457 envelope, serialized with the published wire options rather than
handed to a content negotiator.

Two consequences are deliberate:

- The base is **not** `[ApiController]`. That attribute installs an automatic 400
  for model-state failures in ASP.NET's own `ValidationProblemDetails` shape, so
  a service would emit two error contracts. Without it a malformed body reaches
  the action as a null model and the action returns a typed problem.
- A problem the consumer never registered renders as 500 with an `about:blank`
  type. A documentation URI for an unregistered problem would 404, which is worse
  than admitting the contract is unknown.

## System routes

`GET /system/version` reports the service-tree coordinates and build version.
`GET /system/health` reports `serving` with the instant it answered, as an RFC
3339 UTC string. Both paths are fixed: they are read by tooling that has no
access to a service's configuration.

## OnboardSync

`/internal/onboard-sync/phase` and `/internal/onboard-sync/complete` host the
published auth-engine `OnboardingCoordinator` over HTTP. The onboarding decision
stays in auth-engine; only the endpoints live here. The phase crosses the wire as
its snake_case name — `complete`, `select_landscape`, `awaiting_sync` — never as
an ordinal.

## Webhook receiver

`POST /internal/webhooks/{provider}` implements the C0 §11 wire contract. The
order of checks is load-bearing:

1. **Signature over the raw bytes**, before the media type and before any
   parsing. `HMAC-SHA256(ASCII(t) || 0x2e || body, key)` compared in constant
   time against **every** live rotation key, inside a bounded timestamp window.
   Failure is **401**, never 421.
2. Media type exactly `application/vnd.atomi.webhook.v1+json`, else 415.
3. Envelope validated field by field, else 400 naming the field.
4. Dispatch to the registered handler.

The reply is tri-state: exactly **200** completes the delivery obligation,
exactly **421** means "not mine", and everything else is a real endpoint failure
mercury retries with backoff for 72 hours. **404 is never an ownership signal**
— mercury reads it as a real failure. An unregistered provider and a handler that
disowns an event both answer 421.

Handlers must be idempotent: mercury acks the provider before endpoint
obligations finish, so retries and cross-landscape provider retries can both
duplicate work. `WebhookIdempotency.KeyOf` composes the
`(tenantId, routeId, dedupId)` key with each component length-prefixed, so two
different triples cannot collide into one dedup entry.

## Configuration

`ServerEngineConfig` is the engine-owned block, exported next to the code that
reads it. The config library remains the only merger and validator of the
composed root schema. Only the webhook timestamp tolerance is configurable, and
only **downward**: a receiver may want a tighter window than the contract's five
minutes, and a configuration mistake must not widen the replay window the
contract bounds.
