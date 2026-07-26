---
name: diene-api-engine-usage
description: Consume @atomicloud/diene.api-engine safely. Use when registering Kiota TypeScript SDK backends, attaching per-backend diene.auth-engine state, resolving an LPSM client, handling Result-returning SDK methods, configuring bounded transport rescue trips, or using the packaged TestHelper.
---

# Use diene.api-engine

Register API problem definitions once in the application's existing
`ProblemRegistry`. Build one immutable `bindings` list and pass it to
`createApiEngine`; do not add a second client registry.

For each backend:

1. Supply all four `coordinate` fields: landscape, platform, service, and module.
2. Supply the single config-derived `baseUrl` and auth-engine `ResourceKey`.
3. Supply that backend's `IAuth` (`IAuthStateRetriever`) implementation.
4. Return a Kiota-shaped client synchronously from `createClient`, wiring the
   provided `baseUrl` and `fetch` into its request adapter.

Resolve clients and invoke their methods through `Result`; use `match`, `map`, or
`andThen` instead of throwing `unwrap`. Every proxied method returns a
`Result<T, Problem>` and does not reject.

Compose `apiEngineConfigBlockSchema` into the application's config root. The
schema fixes retry to `OPAQUE_NETWORK_RETRY_ONCE`, requires a positive timeout,
and validates the auth, client-factory, and rescue-trip seams. Use `toResult`
plus the public guards when bridging an SDK value outside the recursive proxy.

Import consumer fixtures from `@atomicloud/diene.api-engine/test-helper` only in
tests.

Read [patterns.md](patterns.md) when implementing registration, rescue behavior,
or consumer tests.
