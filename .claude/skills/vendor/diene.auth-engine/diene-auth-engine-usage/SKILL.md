---
name: diene-auth-engine-usage
description: Use when consuming @atomicloud/diene.auth-engine for Logto auth, backend-scoped onboarding, or deferred mobile app handoff.
---

Import production APIs from `@atomicloud/diene.auth-engine` and test doubles
from `@atomicloud/diene.auth-engine/test-helper`. The package is dual ESM/CJS;
do not import from `dist/`.

Start by calling `createResourceTree(...)` with every backend and its complete
resource set, an explicit KV-backed token store, and injected cache state. The
returned tree is immutable and ready to use; there is no `registerBackend`
setup phase. Keep resource keys as lowercase DNS labels and retain the canonical
key returned by the library rather than rebuilding it in application code. Use
the `IAuthStateRetriever` interface as the seam between the auth engine and
application/API clients.

Call `createOnboardSync(...)` once with all immutable backend/API bindings and
an injected keyed state port. Its phase map is keyed by those backend ids, so a
backend reaching `error` does not imply that other backends are unavailable.
Registration claims are exact string claims, not truthy values; call
`forceTokenSet()` only when the engine needs to reacquire claims after the
single provisioning pass.

For deferred handoff, let an authenticated server mint the nonce, transport
only the canonical carrier text, and redeem it through the configured single
mount. Do not accept a subject or email from a browser/mobile client, do not
branch on failed redemption reasons, and do not make nonce/OTT lifetimes
consumer configuration. The exported `AppHandoffExpired` definition and
`registerAuthProblems` factory use the exact lowercase wire id
`app_handoff_expired`; use `createAppHandoffExpired(...)` for its generic
no-oracle response.

Read [patterns.md](patterns.md) for wiring sketches and boundary rules.

The full authentication standard is maintained in the repository because
`docs/` is outside the published `files` allowlist:
[docs/standards/auth/index.md](https://github.com/AtomiCloud/diene.bun-auth-engine/blob/main/docs/standards/auth/index.md).
