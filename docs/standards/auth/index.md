# Authentication engine

`@atomicloud/diene.auth-engine` keeps authentication mechanics portable across
browser, server, and Workers-style runtimes. Domain code is Web-standard; IO
and Logto/Redis bindings live in adapters.

## Resource tree and tokens

Create a ready `ResourceTree` with the complete immutable backend binding array,
an explicit KV-backed `TokenCacheStore`, and an injected single-flight cache.
There is no later registration step. A resource key has four lowercase DNS
labels: `platform`, `landscape`, `service`, and `resourceName`. Its stable
cache key is `platform/landscape/service/resourceName`; the corresponding
audience is `https://<resourceName>.<service>.<platform>.<landscape>.cluster.atomi.cloud`.

`fetchAllTokens()` snapshots the registrations, deduplicates resources, starts
every acquisition before awaiting a result, and returns a total batch. A token
failure for one backend therefore does not prevent another backend from
receiving its token. The per-resource cache is single-flight: concurrent
refreshes share one request.

Contract lifetimes are fixed rather than configuration knobs:

| Value                  | Lifetime    |
| ---------------------- | ----------- |
| Access token           | 10 minutes  |
| Rotating refresh token | 14 days     |
| Deferred handoff nonce | 15 minutes  |
| Logto one-time token   | 120 seconds |

On an `invalid_grant` or other refresh failure, clear cached credentials and
surface the authentication problem. Consumers can call `forceTokenSet()` to
drop cached tokens and obtain a fresh set.

Logto refresh grants are FIFO-serialized across resource audiences because a
rotating refresh token is single-use. A provider factory creates a coordinator
by default; when multiple provider facades share one session store, inject the
same `LogtoRefreshCoordinator` into all of them.

## Retrievers and onboarding

`IAuthStateRetriever` is the application seam. The server retriever accepts an
`AuthProvider` and a session accessor rather than Node request/response types,
so it can be bundled for an edge runtime. Client retrievers use configurable
auth-state endpoints.

Create `OnboardSync` with the complete immutable backend/API binding array and
an injected state port. It tracks a phase separately for each `backendId`:

| Phase             | Meaning                                                  |
| ----------------- | -------------------------------------------------------- |
| `bootstrapping`   | Resolving that backend's required token set              |
| `needsOnboarding` | Registered, but an app-specific claim is absent          |
| `ready`           | Registration and required application claims are present |
| `error`           | A terminal problem occurred for this backend             |

The registration claim is exact: its key is `<platform>_<service>` with dashes
converted to underscores, and its value must be the JSON string `"true"`.
Absent registration claims trigger at most one `/User/Me`/create cycle, then a
forced token refresh and re-check. Later 401/404 traffic failures move only the
affected backend to `error`; they never restart provisioning.

Before any backend machine runs, use pre-onboarding helpers to check the home
landscape claim. If it is absent, the consumer owns selector UI and may parse
only document-B names and metadata; address or issuer fields are intentionally
rejected.

## Deferred app handoff

The package exports the `AppHandoffExpired` problem definition and the
`registerAuthProblems` factory. This is exact C0 wire parity: the definition's
wire id is lowercase `app_handoff_expired` (status 410), and
`createAppHandoffExpired(...)` creates that registered problem with the generic
`This app handoff is expired or invalid.` detail. `AppHandoffExpired` is the
single observable problem for malformed, expired, replayed, suspended, missing,
or email-rebound handoffs.

The server mints a 32-byte base64url nonce from an authenticated session and
stores its `sub`, email, expiration, and state. Public deferred records expose
`expiresAt` as `Temporal.Instant`; only the Redis adapter serializes that instant
to an RFC 3339 storage value. The canonical carrier is
`atomi-app-handoff:v1:<nonce>`; Android receives it as a percent-encoded
`app_handoff` referrer field and iOS receives the canonical text.

Redeeming a nonce is fail-closed. The store atomically moves it from active to
claimed, checks the current user identity once, mints the 120-second Logto
one-time token, and marks the nonce consumed before replying. Malformed,
expired, replayed, suspended, missing, or email-rebound inputs deliberately
produce the same `AppHandoffExpired` problem so callers cannot use the endpoint
as an account oracle.

The package provides domain and adapter machinery, not an HTTP host. Hosts use
one configurable mount (default `/app-handoff`) for `POST {mount}` and
`POST {mount}/redeem`; never append a second `app-handoff` segment.

## Configuration and tests

`authEngineConfigSchema` owns the `logto`, `handoff`, and Redis `store` block.
Secrets are injected by the consuming configuration path and must not be placed
in YAML or source literals.

For tests, import only from
`@atomicloud/diene.auth-engine/test-helper`. It provides scripted providers and
retrievers, an in-memory deferred store, phase fakes, and token/problem
builders. Production code must import from the package root.
