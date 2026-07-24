# API engine domain contract

See the [API client standard](../standards/api-client/index.md) for the public
registration walkthrough and Result-typed call convention.

## Registration and identity

`createApiEngine` is the single backend registration point. It accepts an
immutable, complete binding list; there is no later `register` mutation. A
backend identity always contains landscape, platform, service, and module, and
duplicates or missing resolutions are returned as `Result` failures.

Each binding has one configuration-derived absolute base URL. Callers cannot
provide or replace a hostname at invocation time. The synchronous client factory
receives only that normalized `baseUrl` and its backend-scoped `fetch` function.

## Kiota structural contract

Api-engine does not depend on generated SDK classes. A client is structurally
Kiota-shaped when it is a synchronous object with callable methods and optional
nested request-builder namespaces. The recursive proxy preserves each method's
`this`, leaves Promise-valued properties untouched, and catches synchronous
throws and rejected promises.

Every proxied method immediately returns `Result<T, Problem>`. It never rejects,
so consumers use `match`, `map`, and `andThen` as the only runtime failure
convention.

## Reconciliation

| SDK/transport outcome                                                        | Result                              |
| ---------------------------------------------------------------------------- | ----------------------------------- |
| Typed/direct value                                                           | `Ok(value)`                         |
| Successful JSON `Response`                                                   | `Ok(parsedJson)`                    |
| Successful non-JSON or stream `Response`                                     | `Ok(response)` without consuming it |
| Direct or nested RFC 9457 Problem                                            | `Err(problem)`                      |
| JSON server failure without a Problem                                        | `Err(ApiUpstreamFailure)`           |
| Non-JSON, status-only, stream, network, timeout, abort, or body-read failure | `Err(ApiTransportFailure)`          |

All engine-authored failures are definitions registered in
`@atomicloud/diene.problems`; api-engine has no local registry or type-URI
builder.

## Multi-backend authentication

Every binding supplies its own published `IAuthStateRetriever` and auth-engine
`ResourceKey`. Construction derives the `CanonicalResourceKey` with
`canonicalResourceKey`. Before a request, the wrapper calls `getTokenSet`; when
the resource token is absent it calls `forceTokenSet` once, then reads only that
canonical entry from `TokenSet.accessTokens`. A caller-supplied Authorization
header is replaced, preventing token bleed between backends.

## Retry and rescue ownership

A returned HTTP `Response` proves a status was received and is never retried.
Thrown SDK errors carrying a status are also never retried. Only opaque,
no-status transport failures receive exactly one retry (two total attempts).
Timeout and caller abort are classified directly and are not retried.

If both opaque attempts fail and rescue is enabled, api-engine calls the injected
`trip` callback once. The callback is an observation/handoff seam: routing,
failover, and the rescue router remain application responsibilities.

## TestHelper

Import `@atomicloud/diene.api-engine/test-helper` for scripted Kiota-shaped
clients/backends, `FakeAuthStateRetriever`, canonical resource fixtures, real
`Response` builders, and Problem assertions. The helper deliberately builds
Problems through `diene.problems` and resource keys through auth-engine so fake
and real contracts stay aligned.
