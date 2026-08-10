# Auth-engine consumer patterns

## Backend-scoped wiring

1. Create an `AuthProvider` for the current authenticated session. If several
   Logto provider facades share one token store, give them the same
   `LogtoRefreshCoordinator` so rotating refresh grants remain serialized.
2. Call `createResourceTree(...)` with every backend, its onboarding resource,
   an explicit KV store, and injected cache state. Treat factory failure as a
   configuration problem; do not expose a partially configured tree.
3. Expose a `ServerAuthStateRetriever` (or browser retriever) to application
   code as `IAuthStateRetriever`.
4. Call `createOnboardSync(...)` once with the same immutable backend ids, an
   injected keyed state port, and each backend's `/User/Me`/create adapter.
5. Treat each phase independently. Render/retry the failed backend rather than
   globally resetting authentication.

## Deferred handoff

1. Mint the nonce server-side from the validated session.
   Deferred `expiresAt` values remain `Temporal.Instant` in domain code; do not
   convert them to strings or epoch milliseconds outside a storage adapter.
2. Emit `atomi-app-handoff:v1:<nonce>` through the Android referrer helper or
   iOS clipboard helper.
3. On app open, parse the carrier and redeem it at the configured mount.
4. If redemption reports `AppHandoffExpired`, fall back to normal interactive
   login. Do not start a carrier-specific retry loop or distinguish replay,
   expiry, or identity failures to users.

## TestHelper

Use `FakeAuthProvider`, fake retrievers, `InMemoryDeferredStore`, phase fakes,
and builders only through the `/test-helper` subpath. Script provider results
so a consumer test can cover refresh failures and per-backend isolation without
calling Logto or Redis.

## Avoid

- Do not deep-import `src`, `dist`, adapters, or test-helper implementation
  files.
- Do not share a single onboarding phase across backend ids.
- Do not make the fixed access-token, nonce, or one-time-token lifetimes
  configuration values.
- Do not put Logto app secrets or management credentials in checked-in config.
