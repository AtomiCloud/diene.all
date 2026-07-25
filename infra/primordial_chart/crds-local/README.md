# Local-only CRD fixtures

**Test-only. Never installed into a real cluster.**

`.helmignore` excludes this directory from the packaged chart, and it is
deliberately NOT named `crds/` — Helm would auto-install that.

A bare k3d cluster has none of the CRDs either chart depends on, so the local
two-chart install smoke applies these minimal stand-ins first. Each is a
structural placeholder (`x-kubernetes-preserve-unknown-fields: true`) that lets
the API server accept the rendered CRs. They assert **install**, not schema
conformance — the real schemas are owned by the dependency operator, the logto
operator, the error portal (T3), external-secrets, and the Grafana Operator.

This mirrors the `charts/carbon` precedent (`tests/fixtures/crds/`), relocated
inside the chart because this repository's `tests/` tree belongs to the
application test tiers.

```sh
kubectl apply -f infra/primordial_chart/crds-local
```

| File                        | Stands in for                              | Real owner          |
| --------------------------- | ------------------------------------------ | ------------------- |
| `platformdependency.yaml`   | `fleet.atomi.cloud/PlatformDependency`     | dependency-operator |
| `logtoapp.yaml`             | `fleet.atomi.cloud/LogtoApp`               | logto-operator      |
| `problem.yaml`              | `atomi.cloud/Problem`                      | T3 / error portal   |
| `externalsecret.yaml`       | `external-secrets.io/ExternalSecret`       | external-secrets    |
| `grafana.yaml`              | the three `grafana.integreatly.org` kinds  | Grafana Operator    |
