# {Service} — System Overview

## What it does

{One short paragraph, plain language, including who its users are.}

## How it works

{Modules and the data flow between them — bullets or a small Mermaid diagram, max ~10 lines.}

## Dependencies

| Direction | System       | Purpose | When it fails, this service… |
| --------- | ------------ | ------- | ---------------------------- |
| calls     | {downstream} | {why}   | {behavior}                   |
| called by | {upstream}   | {why}   | {behavior}                   |
| stores    | {db/queue}   | {what}  | {behavior}                   |

## Failure modes

- {Dominant failure mode 1 — one line}
- {Dominant failure mode 2 — one line}

## Common commands

| Purpose                     | Command                                                                   |
| --------------------------- | ------------------------------------------------------------------------- |
| Pod status                  | `kubectl get pods -n {namespace}`                                         |
| Recent errors (LogQL)       | `{service="{service}", landscape="{landscape}"} \| json \| level="ERROR"` |
| Request rate (PromQL)       | `sum(rate({metric}_total{service="{service}"}[$__rate_interval]))`        |
| {Key domain query} (PromQL) | `{query}`                                                                 |
| Slow traces (TraceQL)       | `{ resource.service.name="{service}" && duration > 2s }`                  |
| Rollout restart             | `kubectl argo rollouts restart {workload} -n {namespace}`                 |

## Links

- [Curated dashboard]({url}) · [Generic dashboard]({url-with-lpsm-vars})
- [Deployment]({url}) · [Docs/TRD]({url})
