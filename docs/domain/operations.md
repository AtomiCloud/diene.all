# Mercury operations

<!-- ### mercury -->
<!-- #### source: mercury -->

Operations are landscape-aware. Events, attempts, queues, circuits, and DLQs
remain in the landing landscape; management truth and console authorization
remain in Neon.

## Real dependency claims

Every serving installation must prove, not merely name:

- one reachable Neon/Postgres management claim pinned through the platform's
  normal placement;
- one distinct reachable Upstash `kv` claim per serving landscape;
- a writable Tigris archive claim with read-after-write verification;
- the Infisical/ExternalSecret chain for provider, tenant, and delivery keys;
- Route 53 landing record metadata for every public serving landscape; and
- ordinary observability sinks for application metrics, JSON logs, traces,
  dashboards, and alerts.

SIT fails closed when any identity, health check, or proof is absent. It must
also prove the two landscape Upstash identities are not aliases and that Neon
is not called during provider intake.

## Console fan-in and replay

The product console uses real account login. Fleet operators use the default
internal account; external accounts see only authorized tenant slices. There
is no CF Access or separate replay-admin service.

Queries fan out to landscape event sources and return source landscape on each
row. Filters include landscape, tenant, provider, endpoint, status, circuit,
and time. Partial landscape failure is visible as partial data with an error;
it must not be presented as a complete empty result.

Replay is sent to the landscape that owns the retained event. The audit record
includes actor/account, tenant, event, endpoint or event-wide scope, source
landscape, request time, result, and new attempt. D11 hides preview callback
delivery visibility only; it does not fabricate success or suppress ordinary
production evidence.

## Apple backfill

Apple Server API recovery runs as a singleton on the preferred-host landscape
of the management DB claim:

1. Acquire the singleton lease and checkpoint the provider cursor.
2. Fetch missed notifications with the registered app/environment credentials.
3. Feed each signed notification through the ordinary verify, dedup, atomic
   acceptance, and delivery pipeline in that landscape.
4. Advance the cursor only after accepted/duplicate outcomes are durable.
5. Alert after more than two consecutive missed cycles.

Backfill must not bypass verification, dedup, fan-to-all, signature, metering,
or retention behavior. Multiple serving landscapes must never multiply the
fetch job.

`operationKey` is the durable namespace for the Apple history cursor. Change
the key, or explicitly reset its saved cursor, whenever the configured history
request window or filters change. A saved page token belongs only to the
request that produced it; reusing it with a different window or filter set is
forbidden.

## Google Play RTDN subscription

The reconciled Pub/Sub push subscription contract requires:

- message retention of exactly 31 days;
- an explicit dead-letter topic/policy, never provider default behavior;
- an OIDC push token from the registered service-account email;
- audience equal to the explicitly configured value or exact stored push URL;
- delivery to the registered Mercury route; and
- continuous drift detection and repair for retention, DLQ, push URL, OIDC
  identity, and audience.

Drift is operationally visible. Reconciliation must not log tokens or rewrite
Mercury event DLQ state; the Pub/Sub DLQ and Mercury endpoint DLQ are distinct.

## Route 53 landing metadata

Public canonical and custom-domain-CNAME traffic lands through direct Route 53
geoproximity A record sets. For each DNS name:

- every set uses geoproximity; policy types are never mixed;
- `SetIdentifier` is stable and unique;
- exactly one of `Coordinates`, `AWSRegion`, or `LocalZoneGroup` is supplied;
- Mercury uses coordinate strings with no more than two decimal places;
- bias is an integer from -99 through 99 (normally 0);
- TTL is 60 seconds;
- only healthy, non-empty landscape ingress IP sets are upserted; empty sets
  are deleted; and
- equivalent groups exist in the primary delegated and backup Route 53 zones.

Route 53 steering improves landing stability and dedup hit rate. It is not an
exactly-once mechanism; correctness remains at-least-once plus idempotency.

## Signals and service levels

Metrics and structured logs carry landscape and tenant attribution where safe:

- intake count/latency/status and quota rejection;
- verification failure by provider and safe reason class;
- atomic acceptance latency/failure and dedup hit rate;
- event/obligation counts, queue depth, oldest age, retry depth, and delivery lag;
- endpoint result, consecutive-failure duration, circuit state, and DLQ depth;
- stale-map `421`, recompile request/result, and refreshed retry result;
- config generation desired/active/acked per landscape;
- console fan-in partial failures and replay audit results;
- Apple cycle/cursor/lease/missed-cycle state;
- Google subscription drift dimensions;
- archive bytes, checksum, success/failure, blocked deletion, and oldest
  unarchived partition; and
- dependency health without credentials or payload bodies.

Alert on durable acceptance failure, growing/aged queues, DLQ growth, 24-hour
endpoint failure, config generation lag, repeated `421`, archive block, Apple
missed cycles, Google drift, dependency identity mismatch, and secret rotation
stalls.

## Runbooks

### Provider receives `5xx`

1. Identify landing landscape from access/DNS metadata.
2. Check local Upstash health and atomic acceptance failures.
3. Confirm no partial dedup/event/queue state exists for the request identity.
4. Restore the local dependency or application; let the provider retry.
5. Never manufacture `200` or a dedup guard by hand.

### Delivery backlog or open circuit

1. Filter by landscape, tenant, and endpoint; inspect oldest attempt and result.
2. Validate destination DNS/TLS/network and internal signature key rollout.
3. For `421`, confirm one recompile and same-endpoint refreshed retry occurred.
4. Repair the endpoint, then use a probe or manual re-enable.
5. Replay only after consumer idempotency and capacity are confirmed.

### Config generation stuck

1. Compare desired, written, active, and acked generation per landscape.
2. Confirm T3 successfully called the management API; do not grant it KV access.
3. Check Mercury compiler, endpoint resolution, and that landscape's Upstash.
4. Leave the last complete generation active while retrying N+1.
5. Never flip `cfg:gen` to a partial generation.

### Archive deletion blocked

1. Preserve the live stream and inspect Tigris permission/upload/checksum errors.
2. Repair the archive dependency or credential chain.
3. Rerun the idempotent archive and verify manifest coverage.
4. Allow deletion only after durable success evidence exists.
