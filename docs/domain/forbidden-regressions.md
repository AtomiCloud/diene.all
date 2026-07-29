# Forbidden design regressions

<!-- ### mercury -->
<!-- #### source: mercury -->

The following artifacts and behaviors are absent by design. Their appearance in
runtime code, charts, scripts, workflows, or configuration is a release blocker,
not an alternative implementation.

## Cloudflare webhook machinery

Mercury must contain none of these webhook-specific artifacts:

- a Cloudflare Worker intake or delivery runtime;
- a D1 event or management database;
- Worker KV configuration or event storage;
- Cloudflare secret bindings for provider or delivery credentials;
- a Wrangler build, version, deploy, or release path;
- a `workers.atomi.cloud` webhook intake name;
- a webhook child `CloudflareDeploy` resource or activation step;
- an orange/proxied webhook route;
- a buffer Worker or “all clusters down” latent buffer option; or
- a CF Access replay/admin hostname or host-header surface split.

CloudflareDeploy may still exist in separately owned frontend and Erbium flows.
An absence check must scope to Mercury/webhook artifacts rather than deleting
unrelated valid uses.

## Election, stamping, and failover machinery

Mercury must not reintroduce:

- logical-copy grouping or collapse;
- nearest-copy, exactly-one-owner, or landscape-owner election;
- owned/no-owner/double-owner bookkeeping;
- landscape stamping in provider payloads or adapter metadata;
- consumer probing to discover entity ownership;
- `421` as “not my landscape” or a sibling-selection signal;
- cross-endpoint fallback ladders or delivery to a sibling after failure;
- fan-out cardinality derived from region count instead of registrations;
- a cross-landscape event sequencer or FIFO guarantee; or
- a global event store used to coordinate delivery ownership.

Every registered endpoint remains an independent obligation. Locality resolves
its address only. Route 53 health trimming is public ingress availability, not
endpoint-obligation failover.

## Control-plane ownership violations

Forbidden control-plane shapes include:

- T3 or the fleet controller writing any per-landscape Upstash config key;
- T3 holding Upstash write credentials or deploying Mercury;
- more than one config compiler/writer for tenant and route generations;
- treating Upstash-derived config as long-lived source of truth;
- provider or delivery secret values in CRs, Upstash, logs, events, or status;
- config pointer activation before every N+1 key is complete; or
- deleting a prior generation without reader/grace safety.

T3 compiles CR fragments into management API calls. Mercury alone compiles API
state into generation-swapped landscape configuration.

## Identity and private-path violations

Forbidden identity shortcuts include:

- selecting tenant, authorization, billing, quota, or secret from request `Host`,
  forwarded headers, source IP, namespace, or payload fields;
- reconstructing a URL-inclusive verification input from request headers;
- trusting cluster-local network position without the internal signature;
- edge-only quota, metering, authentication, or access logging;
- a behavior fork between public and cluster-local application paths; or
- making delivery depend on lithium/M2M availability.

Registered custom domains remain lookup/routing aliases, and both paths execute
the same authenticated application behavior.

## Persistence and delivery violations

Forbidden loss or correctness regressions include:

- acknowledging before atomic dedup, event persistence, and all endpoint
  obligations commit;
- leaving a dedup guard after a failed acceptance or refreshing TTL on a hit;
- translating a transient acceptance failure into provider-facing `4xx`;
- using Neon on the intake hot path;
- storing long-lived tenant/account/domain/credential truth only in Upstash;
- sharing one Upstash database across serving landscapes;
- delete-before-archive or deleting after an unverified Tigris upload;
- forwarding provider signature/authentication headers to consumers;
- following delivery redirects or treating non-`200` `2xx` as success;
- documenting exactly-once, ordered, or FIFO delivery;
- omitting consumer idempotency; or
- adding v1 payload transformation or a durable subscriber abstraction.

## Required absence checks

Static release checks scan implementation/configuration surfaces while excluding
this documentation of forbidden terms. They combine literal artifact searches
with semantic review because synonyms such as “primary receiver,” “copy owner,”
or “regional fallback” can recreate the same rejected design without matching
an old identifier.

Reviewers must trace any new intake runtime, data store, delivery selection,
controller credential, hostname-derived lookup, retry target change, or archive
deletion path against this list before approval.
