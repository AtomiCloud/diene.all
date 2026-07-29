# Mercury webhook alert runbook

## No healthy intake

Confirm that the Deployment has ready replicas and that `/health/live`,
`/health/ready`, and `/metrics` respond. Inspect the most recent rollout before
checking dependencies; liveness is dependency-blind.

## Archive blocked

Do not delete the aging Upstash stream. Confirm Tigris credentials and bucket
access, retry the same landscape/tenant/month archive, and verify the archive
object before allowing retention cleanup.

## Delivery backlog

Break the queue down by landscape, tenant, provider, and endpoint. Check open
circuits and delivery latency. Scaling can drain healthy endpoints, but a
single failing endpoint must remain isolated and must never fail over to a
sibling registration.

## Apple backfill missed cycles

`mercury_apple_backfill_missed_cycles` is the durable
`consecutive_missed_cycles` counter for the Apple Server API history singleton,
republished after every cycle and reset to zero by a successful one. More than
two means the preferred-host landscape has failed to reconcile Apple history
for three or more consecutive intervals.

Confirm which landscape holds the singleton lease
(`provider_operation_state.lease_owner` for the operation key). Inspect the most
recent `runtime.job.failure` events and Apple history client errors — expired
JWT signing material, Apple API unavailability, an invalid page cursor, or a
lost lease are the usual causes. The backfill reuses the ordinary intake
pipeline, so it recovers on its own once the underlying dependency is healthy;
the gauge returns to zero on the next successful cycle. Do not disable the
operation to silence the alert.
