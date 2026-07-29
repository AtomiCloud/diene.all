# Storage and retention

<!-- ### mercury -->
<!-- #### source: mercury -->

Mercury separates long-lived management truth from landscape-local operational
flow. No request on the intake hot path depends on Neon or another landscape.

## Ownership boundaries

| Store                              | Scope                               | Authoritative content                                                                                                                       | Forbidden content                                                   |
| ---------------------------------- | ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| Neon/Postgres                      | Mercury vlandscape management plane | External tenants, accounts/default account, immutable homes, custom domains, credential metadata, subscriptions, quotas, internal CR mirror | Intake event hot path, queues, raw secret values                    |
| `WebhookEngine`/`WebhookRoute` CRs | Internal tenant declarative plane   | Internal desired tenant, route, endpoint, and policy intent                                                                                 | Secret values, external tenant truth, runtime events                |
| Upstash                            | One database per serving landscape  | Active derived config, dedup guards, events, endpoint obligations, retries, attempts, DLQ, counters                                         | Long-lived primary truth, secret values, cross-landscape sequencing |
| Tigris                             | Landscape/tenant/month archive      | Immutable archived event partitions and manifest/checksum evidence                                                                          | Active queues or config                                             |
| Infisical to ExternalSecret        | Secret plane                        | Provider verifier values, native credentials, internal delivery keys, live generations                                                      | Events, route truth, metering                                       |

## Failure-atomic acceptance

After verification and validation, Mercury invokes one server-side operation in
the landing landscape's Upstash. It must produce exactly one outcome:

- **duplicate:** an unexpired guard exists; return duplicate with no event or
  queue writes and do not refresh the guard TTL; or
- **accepted:** create the guard with NX and 72-hour TTL, append the full event
  plus the snapshotted endpoint set, and enqueue every endpoint obligation as
  one indivisible commit.

Arguments are validated before mutation and all keys live in the same database.
There is no partial visibility. Accepted commit precedes provider `200`; a
failed commit returns `5xx`, leaves no live guard, and cannot acknowledge a
lost event.

## Dedup keys

The physical key is:

```text
dedup:<b64url(tenantId UTF8)>:<b64url(routeId UTF8)>:<native-or-sha256-dedupId>
```

TTL starts at the accepted commit and is exactly 72 hours in v1. Scope uses
stable opaque IDs, not display names. Dedup is local to the landing landscape;
an event accepted elsewhere is a valid duplicate delivery under the
at-least-once contract.

## Per-landscape operational layout

| Key family                             | Shape                            | Mercury writer              | Retention/use                                           |
| -------------------------------------- | -------------------------------- | --------------------------- | ------------------------------------------------------- |
| `cfg:gen`                              | active generation pointer        | Config compiler             | Atomic generation selection                             |
| `cfg:<gen>:tenant:*`                   | tenant JSON with secret pointers | Config compiler             | Derived, rebuildable                                    |
| `cfg:<gen>:routes:*`                   | route and resolved endpoint map  | Config compiler             | Derived, rebuildable                                    |
| `dedup:*`                              | NX/EX guard                      | Intake engine               | 72 hours                                                |
| `evt:<tenant>:<YYYY-MM>`               | stream                           | Intake engine               | Current two UTC calendar months, then archive           |
| `event:*`, `event-jobs:*`, `job:*`     | event/job values and set         | Intake and delivery engines | Deleted in bounded pages after verified archive         |
| `q:deliver:ready`, `q:retry`           | due-time sorted sets             | Intake and delivery engines | Members removed on completion, DLQ, or archive deletion |
| `q:deliver:claims`, claim-expiry index | hash plus sorted set             | Delivery engine             | Lease expiry, transition, or archive deletion           |
| `q:paused:expiries`, `paused:*`        | sorted set plus endpoint sets    | Delivery engine             | Atomic expiry-to-DLQ, resume, or archive deletion       |
| `dlq:<tenant>:<YYYY-MM>`               | occurrence-keyed hash            | Delivery engine             | Each entry has its own server-timed field deadline      |
| `event-dlq:<event>`                    | occurrence-keyed hash            | Delivery engine             | Same per-entry deadline; removed with retained event    |
| `dlq-endpoint:<tenant>:<endpoint>`     | job-keyed hash                   | Delivery and replay engines | Per-job expiry; bounded endpoint-only replay            |
| `dlq-months:<tenant>`                  | month-keyed hash                 | Delivery engine             | Latest retained entry keeps only its month field live   |
| `archive:<tenant>:<YYYY-MM>`           | fenced state hash                | Retention manager           | Live/exporting/deleting phase, version, lease, manifest |
| quota/meter counters                   | expiring counter/hash            | Application                 | Exported to observability/billing                       |

These are components of one Mercury product. T3 is not a writer in any key
family.

## Config generation swaps

Mercury is the single config-plane writer:

1. Compile registered tenant/route/endpoint state for one landing landscape.
2. Allocate N+1 and write every generation-scoped key with secret pointers.
3. Validate completeness and address resolution.
4. Atomically set `cfg:gen` to N+1.
5. Record the landscape acknowledgement and expose degraded status for partial
   fan-out.
6. Delete N only after the grace period and after no reader requires it.

A partial write never changes `cfg:gen`. Loss of a derived generation triggers
rebuild from Neon/internal CR mirror; it never promotes Upstash to durable
management truth.

## Event retention and archive-before-delete

Events are partitioned by landing landscape, tenant, and UTC month. The current
UTC month and its predecessor remain live by default; a sparse older month is
still archived even when there are only one or two physical partitions.

For an aging partition:

1. Refuse archival while the month has a pending or paused obligation.
2. Acquire a durable lease over the month's version and freeze the exact stream
   cursor. Intake and replay reject a live lease. If an export lease expires,
   a successful intake/replay advances the version and fences the stale owner.
   A sealed deletion phase rejects replay even after lease expiry.
3. Read at most the configured event count and byte budget into one archive
   part. Jobs and entry-retained DLQs are scanned in bounded batches; the store
   never materializes a whole month or an unbounded DLQ hash.
4. Write each part to Tigris at
   `<landscape>/<tenant>/<month>/versions/<version>/parts/<part>.json`. Verify
   every write with head, byte-length, and SHA-256 read-back before continuing.
   Versioned object paths prevent a stale exporter from overwriting a newer
   archive.
5. Write and verify a compact manifest at the same version root. It records the
   frozen cursor, counts, aggregate bytes, and rolling digest over ordered part
   receipts and cursor ranges.
6. Seal the verified manifest under the same lease/version, then delete jobs
   and events in bounded fenced pages. Only a fully empty frozen stream may
   complete and remove the month, attempt stream, DLQ hashes, and indexes.
7. Record durable archive success and emit the success metric. The authenticated
   `retention:run` maintenance operation invokes this same manager instance and
   reports only its archived/live month receipt.

Any upload, read-back verification, manifest, lease, storage, or permission
failure pages the archive runbook, records failure, and blocks deletion. Retry
is idempotent. Operators must not bypass the block to recover capacity; they
fix Tigris/credentials and rerun verification.

There is intentionally no permanent `q:deliver` append-only stream. The ready
and retry sorted sets are authoritative, while exact job values hold delivery
state. Replay and endpoint resume use a single Lua compare-and-swap over the
stored job bytes, claim ownership, queue indexes, paused indexes, and archive
version. A stale reader cannot overwrite a concurrent transition or report a
false success.

Paused jobs carry a durable retry-horizon score. Replicas may race the due
scan, but the status/bytes compare-and-swap admits exactly one transition to a
dated DLQ entry. The transition captures Redis `TIME`, stores that acceptance
timestamp with the entry, and applies one absolute `HPEXPIREAT` deadline to
every occurrence field and its replay metadata. A later append therefore
cannot extend an older occurrence, and an older occurrence cannot force a
newer one to expire prematurely. When the last field ages out, Redis removes
the empty hash without a cleanup read. The month field is aggregate metadata:
each append replaces it with the latest server acceptance and matching field
deadline, so it exists exactly while at least one entry in that month may
remain. The removed `dlq-month-expiries:*` family is legacy state and must never
be recreated.

DLQ fields are named by encoded job identity plus replay count. Tenant/month
and event hashes store the server acceptance timestamp followed by the entry;
endpoint hashes store that timestamp followed by the exact dead-letter job
bytes used for compare-and-swap. Endpoint-wide replay scans only its
tenant/endpoint hash, inspects at most 1,000 fields, cleans at most 1,000
observed stale fields with compare-and-swap, and replays at most 100 retained
obligations. It never scans unrelated tenant traffic.

`DeadLetterPage` ordering is intentionally opaque. `HSCAN` does not provide a
global order, and a secondary sorted-set membership could outlive the expiring
hash field. Redis cursor scans are at-least-once and may repeat a field,
especially while field expiration mutates the hash. Consumers must traverse
the returned cursor, de-duplicate repeated identical entries by the complete
returned entry tuple (or a canonical serialization of it), and must not infer
newest-first ordering from the in-memory fake. A field retained throughout a
stable traversal is not lost. The opaque cursor carries over-fetched field
names, is capped at 256 KiB, accepts at most 1,000 pending fields, and every
call inspects at most 1,000 fields across at most 64 scans.

### Upstash command compatibility

The production representation uses only commands in Upstash's current
[Redis API compatibility catalog](https://upstash.com/docs/redis/overall/compatibility):

| Commands                                       | Use in the DLQ representation                                      |
| ---------------------------------------------- | ------------------------------------------------------------------ |
| `EVAL`, `TIME`, `TYPE`                         | Atomic transition, server acceptance time, and type preflight      |
| `HSET`, `HGET`, `HMGET`, `HEXISTS`, `HLEN`     | Write and read entry, endpoint, and month fields                   |
| `HSCAN`, `HDEL`                                | Bounded cursor reads and fenced replay/archive cleanup             |
| `HPEXPIREAT`, `HPTTL`                          | Absolute per-field expiry and compatibility/retention verification |
| `PEXPIREAT`, `DEL`                             | Short-lived capability probe containment and removal               |
| `GET`, `SET`, `MGET`, `ZSCORE`, `ZREM`, `SREM` | Existing job CAS and queue/index transition in the same script     |

Upstash documents Redis protocol support through version 8.2, and its
[April 2025 changelog](https://upstash.com/docs/redis/overall/changelog)
records the addition of hash-field expiration, including `HPEXPIREAT` and
`HPTTL`. The dedicated
[`HPEXPIREAT` command reference](https://upstash.com/docs/redis/sdks/ts/commands/hash/hpexpireat)
specifies the absolute Unix-millisecond timestamp and the per-field integer
result (`1` means the expiry was installed).

Before changing any job or DLQ/index datum, the Lua transition writes a
dedicated probe field, gives the probe key a safe whole-key `PEXPIREAT`, and
requires `HPEXPIREAT` to return `1`. An unavailable command or different return
semantics returns storage-unavailable and leaves the delivery job and all user
DLQ/index state unchanged; only the already-bounded probe may remain. Mercury
does not fall back to a whole-key TTL because that would either slide an older
entry's deadline or delete a newer obligation early.

Console replay reads live streams or explicitly restores the archived event to
the original landscape context. The replay obligation retains the original
event and endpoint identities and receives a fresh delivery signature.
