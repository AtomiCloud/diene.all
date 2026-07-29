# Registration and delivery

<!-- ### mercury -->
<!-- #### source: mercury -->

A registration is an endpoint obligation, not a logical copy. Mercury snapshots
all registrations matched by the accepted route and delivers independently to
every endpoint in that snapshot.

## Registration semantics

Internal tenants are declared by one `WebhookEngine` plus consumer-owned
`WebhookRoute` fragments. T3 merges and validates those fragments, then calls
Mercury's management API. External tenants register explicit HTTPS endpoints
through the same product API.

Provider and endpoint signing material is selected through opaque credential
records owned by the same account and tenant. Tenant-facing mutations never
accept mounted-secret references directly; compilation resolves live and
non-expired overlap generations server-side, while delivery emits with the one
live signing credential bound to the snapshotted endpoint.

Within a tenant, registered path is unique. A duplicate path makes the newer
fragment conflict; it never silently overwrites the first. Provider adapter or
explicit scheme must be known, and shared scalar configuration must agree.

Acceptance snapshots stable endpoint IDs:

- additions after acceptance do not receive the old event;
- removals after acceptance do not erase an existing obligation; and
- replay uses the same snapshotted endpoint identities.

## Bounded registration and fan-out

The control plane and runtime enforce the same v1 ceilings before publishing a
generation or atomically accepting an event:

| Bound                                     | Maximum |
| ----------------------------------------- | ------: |
| Routes per tenant                         |      64 |
| Endpoints per route                       |      64 |
| Total endpoint fan-out entries per tenant |     512 |
| Compiled configuration document           |   4 MiB |
| Serialized atomic intake command          |   4 MiB |

A generation above any compiled bound is never activated. Intake also checks
the active generation and the exact envelope/job command size before invoking
atomic persistence, so corrupt or bypassed configuration fails retryably
without partial acceptance.

## Fan-to-all cardinality

| Registered shape                              | Obligations per accepted event |
| --------------------------------------------- | -----------------------------: |
| One vlandscape or external URL                |                              1 |
| Three distinct per-row endpoint registrations |                              3 |
| N matched endpoint registrations              |                              N |

No runtime election, collapse, owner selection, or “nearest single copy” may
change this cardinality. Failure of one endpoint never redirects its obligation
to a sibling.

## Locality is address resolution

Mercury compiles an address for each `(landing landscape, endpoint)` pair:

| Endpoint registration                           | Address selected                                               |
| ----------------------------------------------- | -------------------------------------------------------------- |
| Coordinate serves the landing landscape         | Cluster-local Service DNS plus `/internal/webhooks/{provider}` |
| Coordinate does not serve the landing landscape | Canonical vlandscape hostname                                  |
| External tenant endpoint                        | Explicit registered HTTPS URL                                  |

Locality changes only where the same obligation is sent. It never adds, removes,
elects, or replaces registrations. A `421` refreshes the address for that same
endpoint once; it does not select a sibling.

External destinations are HTTPS on port 443 only. At every connection Mercury
resolves the registered hostname, rejects the complete answer set if any
address is loopback, private, shared, link-local, metadata, documentation,
multicast, reserved, or otherwise non-public, and pins one approved address to
a one-shot TLS connection while retaining the hostname for SNI and certificate
verification. It re-resolves on the next attempt, which closes DNS rebinding's
validation/connection gap. Redirects are disabled. Platform coordinates remain
separately authorized registrations and use their trusted canonical/local
address path; an external tenant cannot opt into that classification.

## Name-blind and private-path law

Tenant identity, authorization, metering, quota, secret lookup, and signature
input come from registered state and verified credentials. They never derive
from `Host`, forwarded headers, source IP, namespace, or business payload.

Public and cluster-local delivery paths execute identical application logic:

- every request requires the internal delivery signature;
- every request is attributed and metered to the registered tenant;
- quotas and access logs are enforced in-app; and
- network policy is defense in depth, not authentication.

Custom-domain `Host` is an exact registered lookup hint only. URL-inclusive
verification uses the stored registered URL.

## At-least-once, unordered

Delivery is **at-least-once and unordered**. Provider retry, acknowledgement
before delivery completion, endpoint retry, replay, and another-landscape
landing can all duplicate processing. There is no cross-landscape sequencer;
same-endpoint rough FIFO is incidental.

Every consumer must apply a domain idempotency key, normally
`(tenantId, routeId, dedupId)`. `attempt`, arrival order, and `eventId` alone
are not domain correctness keys. Provider sequence/timestamp and Mercury
receive metadata may help reconstruct order but do not create an ordering
guarantee.

## Retry, circuit, and DLQ

Retry state belongs to one endpoint obligation:

1. Exact `200` completes it.
2. `421` alerts, requests a config recompile, and retries the same endpoint
   once at the refreshed address.
3. All other statuses and transport failures back off exponentially from
   seconds to minutes to hours.
4. The default horizon is 72 hours; a tenant may shorten it but not lengthen it
   beyond the product cap.
5. Exhaustion appends the obligation to the landing landscape's tenant DLQ.

About 24 hours of continuous endpoint failure opens that endpoint's circuit.
New active retries pause and the console marks the endpoint unhealthy. A
successful probe or manual re-enable closes it. Other endpoints continue
independently. Pausing also enters the obligation in a durable expiry index;
every ordinary delivery tick moves due paused jobs to the DLQ at their retry
horizon even when the circuit never recovers.

## Replay

The console can replay one event or one endpoint from the landscape that owns
the retained event. Replay:

- reuses the snapshotted endpoint identity and payload;
- increments `attempt` and sets `delivery.replay=true`;
- creates a fresh timestamp and internal signature;
- is audited to account, tenant, operator, source landscape, event, endpoint,
  and result; and
- follows the same auth, quota, metering, retry, circuit, and DLQ rules as an
  initial attempt.
