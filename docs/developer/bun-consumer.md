---
id: bun-consumer
title: Bun Consumer
---

# Bun consumer

This template builds one background-worker artifact with three subcommands:
`worker` consumes Redis Streams, `db-init` checks dependencies and applies
idempotent migrations/seeds, and `health` checks only the worker heartbeat.
There is no HTTP or cron surface.

Configuration loads `config/settings.yaml`, then the selected
`config/<landscape>.settings.yaml`, then build-time and runtime `ATOMI_`
overrides. Double underscores address nested keys; a blank environment value is
unset. Regenerate the committed schema with `scripts/local/schema-gen.sh` and
export the published Problem catalog with `scripts/local/problems-export.sh`.

Use `pls dev`, `pls run -- <subcommand>`, or `pls preview -- <subcommand>` for
the three runtime shapes. `pls up` and `pls down` own Postgres, Redis, MinIO,
Alloy, ClickHouse, VictoriaMetrics, and Grafana. `pls test:unit`,
`pls test:int`, and `pls test:sit` run the pure, adapter, and compiled-binary
tiers; `pls test:sit:coverage` runs the same journeys in process.
