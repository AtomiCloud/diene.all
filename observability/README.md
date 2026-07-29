# Mercury observability

Mercury emits landscape-local Prometheus metrics and structured JSON logs. The
app chart installs the ServiceMonitor, alert rules, and dashboard material.
Every signal carries `platform=mercury`, `service=webhook`, `module=hooks`, and
the serving `landscape`; tenant labels are bounded identifiers and never secret
values.

The alert rules intentionally cover the loss-prevention boundaries: no healthy
intake, retention blocked by an archive failure, and sustained delivery
backlog. See the runbook in `alerts/mercury-webhook.md`.
