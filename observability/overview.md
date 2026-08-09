# `{Service}` — System Overview

## What it does

`{One short paragraph, in plain language, including who uses the service.}`

## How it works

`{Describe the modules and data flow in at most ten lines or a small Mermaid diagram.}`

## Dependencies

| Direction | System         | Purpose  | When it fails, this service… |
| --------- | -------------- | -------- | ---------------------------- |
| calls     | `{downstream}` | `{why}`  | `{behavior}`                 |
| called by | `{upstream}`   | `{why}`  | `{behavior}`                 |
| stores    | `{database}`   | `{what}` | `{behavior}`                 |

## Failure modes

- `{Dominant failure mode one}`
- `{Dominant failure mode two}`

## Common commands

| Purpose               | Command                                                                  |
| --------------------- | ------------------------------------------------------------------------ |
| Pod status            | `kubectl get pods -n {namespace}`                                        |
| Recent errors (LogQL) | `{service="{service}",landscape="{landscape}"} \| json \| level="ERROR"` |
| Request rate (PromQL) | `sum(rate({metric}_total{service="{service}"}[$__rate_interval]))`       |
| Slow traces (TraceQL) | `{ resource.service.name="{service}" && duration > 2s }`                 |
| Rollout restart       | `kubectl argo rollouts restart {workload} -n {namespace}`                |

## Links

- [Curated dashboard]({url})
- [Generic dashboard]({url-with-lpsm-variables})
- [Deployment]({url})
- [Docs or TRD]({url})
