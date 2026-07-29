# Tenancy and management

<!-- ### mercury -->
<!-- #### source: mercury -->

Mercury is one native-multi-tenant product on the dedicated Mercury products
platform. Internal and external tenants use different provisioning doors but
the same management contract and data plane.

## Account and tenant classes

| Class                 | Source of truth                              | Provisioning door            | Endpoint form                                             |
| --------------------- | -------------------------------------------- | ---------------------------- | --------------------------------------------------------- |
| `internal/<platform>` | `WebhookEngine` and `WebhookRoute` CR intent | T3 calls the management API  | Service/module coordinates, eligible for local resolution |
| `external/<slug>`     | Mercury management database                  | Native signup/management API | Explicit HTTPS URLs                                       |

The class is visible in audit, metering, and the console. Intake, verification,
dedup, persistence, and delivery do not branch on it.

Provisioning creates a real default internal account. Fleet automation and
operators authenticate through that account; there is no parallel super-admin,
CF Access, or network-trusted door. External accounts use the same product
surface with tenant-scoped authorization.

## Lifecycle invariants

- Account suspension denies management actions and new intake according to the
  registered policy without deleting retained evidence.
- Tenant deletion fails closed until routes, domains, subscriptions, provider
  credentials, endpoint signing bindings, native credentials, and replay audit
  dependencies are gone. Deleting an empty tenant atomically removes its quota
  and metering rows; cross-account deletion is forbidden.
- Provider removal enters `OrphanedProvider` grace for the retention window so
  a still-live provider can be verified and persisted while operators are
  alerted. A never-registered path remains `404`.
- Tenant mutations select opaque credential IDs and never accept mounted-secret
  paths. Neon binds each ID to account, tenant, provider or endpoint, kind,
  generation, and lifecycle; the compiler rechecks those fields before pointer
  resolution. Verification tries newest live then non-expired overlap keys.
- Account-wide principals with `secrets:provision` may create or rotate
  provider-verification bindings and may create or rotate an endpoint signing
  binding before the endpoint itself is registered by naming its reserved
  endpoint ID. The operations return only opaque binding IDs.
  Mounted references are exactly one logical `/` followed by one flat,
  Kubernetes-safe Secret filename key; hierarchical paths are invalid.
- Tenant-scoped management credentials can rotate only their exact tenant and
  issue only a subset of their own scopes. Global or wildcard issuance requires
  an account-wide delegated principal.

## Immutable home

A tenant's home vlandscape is fixed at creation. Mutation in place is rejected
and alerted. Moving home means:

1. create a new tenant with the target home;
2. register and verify its provider URLs, domains, endpoints, and credentials;
3. cut providers and consumers over explicitly; and
4. retire the old tenant through the normal archive/revocation lifecycle.

There is no tenant-home migration mechanism and no runtime home election.

## T3 and Mercury ownership split (Q-WH13)

T3's webhook controller is a management client only:

1. Merge `WebhookEngine` and consumer-owned `WebhookRoute` fragments.
2. Validate path uniqueness, provider adapters, scalar agreement, quotas, and
   coordinate syntax.
3. Find or adopt the internal tenant and synchronize desired state through one
   Mercury management endpoint using the default internal account.
4. Report reconciliation conditions; if Mercury is unavailable, keep the last
   compiled generation serving and retry management reconciliation.

Mercury alone:

1. stores the internal mirror and all external tenant truth;
2. resolves endpoint coordinates for every landing landscape;
3. writes all keys for generation N+1 in each landscape's Upstash;
4. atomically flips that landscape's active generation pointer; and
5. removes the superseded generation after the grace window.

T3 never receives per-landscape Upstash write credentials, never writes KV,
never deploys Mercury, and never becomes a second config-plane writer. “Compile
CR fragments” means compile them into management API calls.

## Management API responsibilities

The native API owns:

- account and tenant creation, suspension, and retirement;
- route and endpoint registration;
- immutable home and registered intake URL enforcement;
- provider and delivery credential rotation;
- quota, retention, retry, and circuit policy within product limits;
- custom-domain registration and status; and
- subscription metadata, console authorization, and audited replay.

Management and signup may touch Neon. Provider intake and endpoint delivery
must not.

## Custom domains

Mercury declares `customDomains: multi`. Each domain is a tenant attribute and
must be registered before DNS is accepted:

1. Traffic CNAME: the customer host points exactly to Mercury's canonical
   home-vlandscape intake name.
2. ACME delegation CNAME: `_acme-challenge.<customer-host>` points exactly to
   the unique server-issued target returned by registration. The response
   lists both complete records and never exposes the stored claim hash.
3. A fail-closed verifier resolves both names, normalizes answer case and a
   trailing dot, and requires one exact answer for each. Empty, multiple,
   conflicting, malformed, or failed lookups cannot prove ownership; callers
   cannot submit their own success result.
4. Mint the certificate centrally with DNS-01, store it in Infisical, and fan
   it to each serving cluster.
5. Only fully `active` claims enter route validation or compiled host hints.
   DNS-proven claims remain `verified` and unpublished until certificate
   readiness is truthfully available. Pending claims expire after 24 hours and
   are released; they are never authoritative.
6. Materialize the per-cluster HTTPRoute and confirm readiness.
7. Renew through the normal rotation machinery.

Domains are vanity/routing only. They never determine identity, billing, secret
lookup, or authority. Domain removal is rejected until every route has cut its
registered URL over; the reference check parses and compares the exact hostname
and never uses a substring match.

## Hard control-plane boundaries

- At most 1,000 accounts, 128 tenants per account, 64 routes per tenant, 64
  endpoints per route, and 512 endpoint obligations per tenant.
- Compiled configuration is capped at 4 MiB before staging. Management request
  bodies are capped at 1 MiB and request cost is atomically metered per native
  credential and second in Neon.
- External URL endpoints must be HTTPS on effective port 443. Registration
  rejects userinfo, fragments, loopback, private, CGNAT, link-local, metadata,
  documentation, benchmark, multicast, reserved, cluster, and internal
  destinations, including any DNS answer set containing one. Runtime repeats
  this at connection time. Only server-owned coordinates bypass URL policy.
- Landscape query/replay sources are account-owned trust records keyed by
  `(accountId, landscape)`. The API forces the authenticated account, tenant
  credentials cannot mutate them, and accounts cannot list each other's
  operation origins.

## Recoverable generation activation

Each instance compiles exactly its trusted local landscape. Neon keeps
independent per-landscape chains. Publication stages a complete generation,
runs provider and secret preflight, then performs the local Redis CAS. After
CAS the ledger records `activated` before acknowledgement; later failures are
never relabelled `failed`. Reconcile reads the active runtime generation and
hash, repairs acknowledgement and active state, and retains only the same
landscape's predecessor.

Deleting a last route preserves its provider verification and persistence
identity with zero delivery endpoints for 72 hours. The orphan deadline is
carried across generations and the route disappears after expiry.

## Environment decisions

- **D11:** callback delivery visibility for preview tenants remains withheld.
  Tenant and route state can be fresh and observable; the product build and
  ordinary serving delivery are not gated.
- **D7:** preview consumption mode per service and fork source remains open.
  Do not infer shared, forked, or local capacity behavior.
- **D21:** a Mercury engine for developing Mercury in hermetic landscapes
  remains open. The consumable service stays off in rotom/absol unless ruled.
- Lapras has the fresh connected local realization. Ditto, rotom, absol, and
  eevee remain structurally off for the consumable service; castform receives
  fresh tenant/route state subject to D11.
