# Go consumer

This template builds one background-worker artifact with three subcommands:
`worker` consumes Redis Streams, `db-init` checks dependencies and applies
idempotent migrations and seeds, and `health` checks only the worker heartbeat.
There is no HTTP or cron surface, and no hot-reload shell — a worker has no
request loop to iterate against.

Configuration loads `config/settings.yaml`, then the selected
`config/<landscape>.settings.yaml`, then `ATOMI_` environment overrides. Double
underscores address nested keys, lists use contiguous zero-based indexed keys,
and a blank environment value is unset. Only the final merged layer is
validated, and it fails fast. Regenerate the committed schema with
`scripts/local/schema-gen.sh` and export the published Problem catalog with
`scripts/local/problems-export.sh`.

`lib/` holds pure domain packages behind their own port interfaces and carries
the 100% unit ledger; `adapters/` implements those ports against real drivers
and carries the 100% integration ledger; `cmd/go-consumer/` is the single
composition root that wires them. `lib/` never imports `adapters/`.

Use `pls dev`, `pls run -- <subcommand>`, or `pls preview -- <subcommand>` for
the three runtime shapes. `pls up` and `pls down` own Postgres, Redis, MinIO,
Alloy, and the local telemetry backends. `pls test:unit`, `pls test:int`, and
`pls test:sit` run the pure, adapter, and compiled-binary tiers;
`pls test:sit:parity` runs the same journeys through both the compiled and
in-process drivers and refuses when they disagree.

The repository ships two charts. `infra/root_chart` is the application chart:
the worker Deployment, whose liveness and readiness exec probes call
`go-consumer health` and are therefore dependency-blind, plus the db-init Job
as an ArgoCD PreSync hook on an early sync wave. `infra/primordial_chart`
carries the platform CR set. One semver is shared by the image tag and both
chart versions.
