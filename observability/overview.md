# `fleet-operator` — System Overview

## What it does

The fleet-operator is one binary with six controllers (cluster, platform,
dependency, traffic, webhook, cf-deploy), each behind an `--enable` flag and a
scoped token. It reconciles the fleet's CRDs — provisioning clusters, identity
and secrets, datastores, DNS/traffic, webhooks, and edge deploys — from
Primordial, and also runs as a dependency-only subset inside every Garden
instance. On-call platform engineers are the primary users of these signals.

## How it works

Each controller is a level-triggered reconcile loop over a durable R2 ledger
(intent → create → confirm; the source of record lives outside etcd). A new
version deploys in `--observe` mode first — it publishes the would-apply plan
read-only through conditions, metrics, and logs — and a human flips to `active`
only once the plan looks empty. Blast brakes freeze-and-page instead of writing
when a change exceeds a pinned cap.

## Dependencies

| Direction | System                 | Purpose                                 | When it fails, this service…                                      |
| --------- | ---------------------- | --------------------------------------- | ----------------------------------------------------------------- |
| calls     | vendor/provider APIs   | provision external resources            | records `vendor_api_failures`, holds a bad condition              |
| calls     | R2 durable ledger      | source of record for externals          | records `ledger_failures`, refuses unsafe writes                  |
| calls     | mercury management API | internal-tenant/route sync              | records `tenant_sync_failures`, mirrors last state                |
| called by | Prometheus scraper     | scrape the authn/authz metrics endpoint | metrics stop flowing; a declared producer's staleness alert fires |

## Failure modes

- Poll/reconcile loop frozen — surfaced as timestamp staleness (`time()` minus
  `fleet_operator_last_successful_tick_timestamp_seconds`), never averaged away.
  Because that alert pages on an absent series, it is shipped only for the
  controllers declared in the chart's `alerts.tickProducerControllers` — the
  controllers that actually stamp a successful tick. A controller with no writer
  gets no staleness page (it would be a permanent false page, not liveness).
- Blast brake tripped — a `BlastBrakeTripped` condition held True pages; the
  controller freezes rather than applying a pathological change.
- Vendor/ledger API failures, or a webhook landscape stuck behind `cfg:gen`.
  Webhook delivery-path failures are mercury's own signals, not this operator's.

All metric labels are bounded closed vocabularies with a single `other` overflow
(see [Signal decisions](SIGNALS.md)): a controller, vendor, or condition type you
do not recognise on a dashboard is `other`, and the exact value is in the logs and
the CR status.

## Common commands

| Purpose                   | Command                                                                                   |
| ------------------------- | ----------------------------------------------------------------------------------------- |
| Pod status                | `kubectl get pods -n fleet-operator`                                                      |
| Recent errors (LogQL)     | `{service="fleet-operator",landscape="$landscape"} \| json \| level="ERROR"`              |
| Reconcile errors (PromQL) | `sum by (controller) (rate(controller_runtime_reconcile_errors_total[$__rate_interval]))` |
| Poll staleness (PromQL)   | `time() - max by (controller) (fleet_operator_last_successful_tick_timestamp_seconds)`    |
| Rollout restart           | `kubectl rollout restart deploy/fleet-operator -n fleet-operator`                         |

## Links

- [Signal decisions](SIGNALS.md)
- [Alert sets](alerts/README.md)
- [Curated dashboards](dashboards/README.md)
- Generic dashboard and deployment links are landscape-specific; resolve them
  from the platform's Grafana with the LPSM template variables.
