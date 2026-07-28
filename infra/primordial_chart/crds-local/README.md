# Local-only CRD fixtures

**Test-only. Never installed into a real cluster.**

`.helmignore` excludes this directory from the packaged chart, and it is
deliberately NOT named `crds/` — Helm would auto-install that.

A bare k3d cluster has none of the CRDs this chart depends on, so the local
install smoke (`scripts/validate/chart-install.sh`) applies these minimal
stand-ins first. Each is a structural placeholder
(`x-kubernetes-preserve-unknown-fields: true`) that lets the API server accept
the rendered CRs. They assert **install**, not schema conformance — the real
schemas are owned by the logto operator and the Grafana Operator.

```sh
kubectl apply -f infra/primordial_chart/crds-local
```

| File            | Stands in for                             | Real owner       |
| --------------- | ----------------------------------------- | ---------------- |
| `logtoapp.yaml` | `fleet.atomi.cloud/LogtoApp`              | logto-operator   |
| `grafana.yaml`  | the three `grafana.integreatly.org` kinds | Grafana Operator |

## Why only two files, where the backend siblings ship five

`go-consumer` and `bun-consumer` also ship `platformdependency.yaml`,
`problem.yaml`, and `externalsecret.yaml`. This chart renders none of those
kinds: a mobile client owns no database, kv, cache, or object store, it consumes
backend problem types rather than publishing a catalog, and it mounts no
secrets. A fixture for a CR that never renders would make the smoke look broader
than it is.

`grafana.yaml` is kept whole — all three kinds — even though only `GrafanaFolder`
renders today. The dashboard and alert templates ship and are proven to render
(see the parent [`README.md`](../README.md)); the fixtures are what let the
smoke stay honest the moment content lands.
