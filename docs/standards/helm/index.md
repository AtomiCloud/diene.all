# Helm

Helm conventions for Kubernetes chart packaging and deployment. Charts live under
`infra/`, and there may be several — each chart directory is its own chart with its
own task set and its own caller job.

## Structure

Each chart directory under `infra/` follows the standard Helm layout:

- `Chart.yaml` — chart metadata
- `values.yaml` — default values
- `templates/` — Kubernetes manifest templates

## Local development

Local work uses Taskfile one-liners (these never call the CI scripts). The
authoritative list is `tasks/Taskfile.helm.yaml`: it holds one `deps`, `lint`,
`template`, and `debug` task per chart, namespaced by the chart directory's own
name — `infra/root_chart` is `root_chart:<verb>`. Read the task `desc` to see which
chart a task acts on, or run `pls --list`.

Pass extra `helm template` arguments after `--`. Chart linting is available
directly and also runs in `pls lint`. Generated chart docs are produced by
`helm-docs` from each chart's own values; the `a-helm-docs` pre-commit hook
rejects generated documentation drift.

Adding a chart means adding its own task set under its own key. Never generalize
the existing tasks into one `lint` that switches on a shared chart variable.

## CI/CD release structure

Publishing is driven by the `⚡reusable-helm.yaml` reusable workflow, called from `ci.yaml`
(every commit) and `cd.yaml` (release tag):

1. The reusable workflow uses `AtomiCloud/actions.setup-nix` and runs inside `nix develop .#cd`,
   so `helm`/`yq` come from the Nix store. The store is restored from the shared Nix cache —
   one cache for all Nix jobs, no per-service keys (see
   [the service-tree standard](../service-tree/index.md)) — which is why Helm needs Nix while
   Docker does not.
2. It runs [`./scripts/ci/helm.sh`](../../../scripts/ci/helm.sh), which reads the chart path
   and release version from the environment the reusable workflow sets. That script owns the
   published version and destination: read its version assignment to see what a commit build
   versus a release tag publishes, and its push command for where charts land.

In CI, Helm linting runs through the pre-commit hook (not a separate job).

### Adding more charts

Each chart is one caller job — there is **no cap**. Add a job to both `ci.yaml`
and `cd.yaml`, pointing `chart_path` at a chart that exists in that descendant:

```yaml
jobs:
  worker-chart:
    uses: ./.github/workflows/⚡reusable-helm.yaml
    secrets: inherit
    with:
      chart_path: ./infra/<chart>
      version: ${{ github.ref_name }} # cd.yaml only
```

### Configuration

The reusable workflow's inputs are declared in its own `on.workflow_call.inputs`
block in [`.github/workflows/⚡reusable-helm.yaml`](../../../.github/workflows/⚡reusable-helm.yaml).
Read that block for the current set: each entry names the input, whether it is
`required`, and its `default`.

## Out of Scope

Per-landscape values files (e.g. `values.<landscape>.yaml`) are deferred and not part of
the generated scaffold.
