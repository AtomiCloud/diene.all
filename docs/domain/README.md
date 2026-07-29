# Domain documentation

<!-- ### workspace -->
<!-- #### source: workspace -->

Domain-specific architecture and behavior belongs under `docs/domain/`.

<!-- ### mercury -->
<!-- #### source: mercury -->

## Mercury

Mercury is the fleet-wide, multi-tenant webhook product. These documents are
the operational source of truth for its public intake, internal delivery,
management, persistence, and provider behavior.

The authority rules are deliberate:

- T3 is an internal-tenant management client. It sends merged CR intent through
  Mercury's management API using the default internal account.
- Mercury is the only compiler and writer of derived per-landscape Upstash
  configuration. T3 never writes Upstash and never deploys Mercury.
- D7 and D21 remain unresolved. D11 withholds preview callback delivery
  visibility only; it does not gate the product or ordinary delivery.
- Delivery is at-least-once and unordered. Every consumer must be idempotent.

## Documentation map

- [Wire protocol](wire-protocol.md) — public intake, the v1 delivery envelope,
  response semantics, and internal signature verification.
- [Provider adapters](provider-adapters.md) — the seven adapters, verification
  inputs, dedup identities, credentials, and rotation.
- [Registration and delivery](registration-and-delivery.md) — fan-to-all,
  locality, name blindness, retries, circuits, DLQ, and replay.
- [Tenancy and management](tenancy-and-management.md) — accounts, immutable
  home, custom domains, the T3/Mercury split, and preview gates.
- [Storage and retention](storage-and-retention.md) — Neon, per-landscape
  Upstash, Tigris, atomic acceptance, generation swaps, and archive-before-delete.
- [Operations](operations.md) — console fan-in, Apple and Google operations,
  Route 53 landing, observability, alerts, and runbooks.
- [Forbidden regressions](forbidden-regressions.md) — absence requirements for
  Cloudflare, election, stamping, failover, and obsolete ownership machinery.
