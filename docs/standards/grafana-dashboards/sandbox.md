# Grafana Dashboard Sandbox & Verification Reference

Everything needed to run the self-verification loop locally. Copy these files into a
scratch directory (not the repo) unless the project already has a `sandbox/` setup.

All CLI tools used here (`jq`, `dashboard-linter`, `promtool`, `docker`) come from the
repo's **nix dev shell** — add missing ones to `flake.nix` (see the `nix` skill).
Never instruct or perform ad-hoc installs.

## 1. Sandbox: docker compose

`compose.yaml`:

```yaml
services:
  grafana:
    image: grafana/grafana:12.1.0
    ports: ['3000:3000']
    environment:
      GF_AUTH_ANONYMOUS_ENABLED: 'true'
      GF_AUTH_ANONYMOUS_ORG_ROLE: Admin
      GF_RENDERING_SERVER_URL: http://renderer:8081/render
      GF_RENDERING_CALLBACK_URL: http://grafana:3000/
    volumes:
      - ./provisioning:/etc/grafana/provisioning
      - ./dashboards:/var/lib/grafana/dashboards
  renderer:
    image: grafana/grafana-image-renderer:latest
    environment:
      AUTH_TOKEN: '-'
  prometheus:
    image: prom/prometheus:latest
    ports: ['9090:9090']
    volumes:
      - ./prom-data:/prometheus
    command:
      - --config.file=/etc/prometheus/prometheus.yml
      - --storage.tsdb.path=/prometheus
```

`provisioning/datasources/datasources.yaml`:

```yaml
apiVersion: 1
datasources:
  - name: Prometheus
    uid: prometheus # match the datasource uid your dashboard queries
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
  - name: TestData
    uid: testdata # layout prototyping only — cannot run PromQL
    type: grafana-testdata-datasource
    access: proxy
```

`provisioning/dashboards/default.yaml`:

```yaml
apiVersion: 1
providers:
  - name: local
    type: file
    options:
      path: /var/lib/grafana/dashboards
      foldersFromFilesStructure: true
```

Copy the JSONs from `observability/dashboards/` into `./dashboards/` — file provisioning
reloads every ~10s, so edit → save → re-render is the whole iteration loop.

## 2. Synthetic data (so panels render with real lines, not "No data")

TestData cannot execute PromQL, so backfill Prometheus with OpenMetrics series that
match the dashboard's metric names:

```bash
# generate synthetic series (bun script or shell loop) → openmetrics.txt, e.g.:
# http_requests_total{service="checkout",status="200"} 1027 1719999000
# http_requests_total{service="checkout",status="500"} 3 1719999000
# ... one sample per series per 15-60s step, covering now-6h → now, ending with # EOF

promtool tsdb create-blocks-from openmetrics openmetrics.txt ./prom-data
docker compose restart prometheus
```

Rules for the generator:

- Cover **every metric name and label combination** the dashboard queries.
- Include error-path series (5xx, failures) so error panels and thresholds show color.
- Counters must increase monotonically; gauges should vary (test y-axis scaling).

## 3. Render endpoints

```bash
# full dashboard (kiosk hides chrome)
curl -s -o board.png "http://localhost:3000/render/d/<uid>/x?kiosk&width=1600&height=1200&from=now-6h&to=now&tz=UTC"

# single panel
curl -s -o panel.png "http://localhost:3000/render/d-solo/<uid>/x?panelId=<id>&width=1000&height=500&from=now-6h&to=now"
```

- Tall dashboards: raise `height` until the bottom row is visible in the PNG.
- Against a real (non-anonymous) Grafana, add `-H "Authorization: Bearer <sa-token>"`.
- Then **Read the PNG files** and inspect against the [visual checklist](./index.md#visual-checklist-looks-good-defined).

## 4. Lint configuration

`dashboard-linter` checks Prometheus dashboards: datasource/job/instance template
variables, `$__rate_interval` usage, counter aggregation (`rate` before `sum`), panel
titles/descriptions/units, PromQL validity.

```bash
dashboard-linter lint dashboard.json --strict [--fix]
```

Justified exclusions go in a `.lint` file next to the dashboard:

```yaml
exclusions:
  template-job-rule:
    reason: single-tenant dashboard, job selector not applicable
```
