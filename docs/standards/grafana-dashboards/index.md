# Grafana Dashboard Standards

Dashboards are the first thing a responder sees when an alert fires. This article defines how this service writes its Grafana dashboard as code and how the author **verifies the work visually** before shipping: lint, render, look at the result, iterate.

The core rule: **never ship a dashboard you have not seen rendered.** A dashboard that passes JSON validation can still be unreadable — wrong units, flat-lined axes, "No data" everywhere. Only rendering catches that.

Tools: dashboard JSON (v1/"classic" schema) in `observability/dashboards/` (one file per dashboard, `overview.json` first), validated with `jq` + [`dashboard-linter`](https://github.com/grafana/dashboard-linter), rendered in the [docker sandbox](./sandbox.md). The service's primordial chart emits one `GrafanaDashboard` CR per JSON (see [folder layout](../observability/index.md#contract-2-folder-layout--flat-primordial-chart-synced) and the [rendering convention](../observability/primordial-chart.md)).

---

## The Two-Tier Model

Decide the tier before writing a panel:

1. **Generic dashboard (global — not this repo's concern).** RED / Four Golden Signals / SLO panels over standard metrics, driven by LPSM template variables. This service appears in its dropdowns automatically once its metrics carry LPSM labels. Never re-create any of its panels here.
2. **Curated dashboards (`observability/dashboards/<purpose>.json` — earned, not default).** Custom/domain metrics only. Whether this service earns any is a Gate 4 decision in `SIGNALS.md` ([Signal Decisions](../observability/signals.md)); "no curated dashboard" is a valid, good outcome. `overview.json` (uid `<platform>-<service>-overview`) is the one alerts link to; deep-dive dashboards get their own files (uid `<platform>-<service>-<purpose>`) linked from the overview. Never repeat generic-dashboard panels — link across with LPSM variables pre-filled in the URL. **Any panel referenced by an alert's `panel` field must exist in `overview.json`** — dashboards are IaC; reviewers check the panel reference.

Both tiers make `$landscape` (our env) a mandatory template variable — one definition, every environment. The curated dashboard also carries a **logs row** (error-level, LPSM-filtered) and a **traces row** (slow/error traces), so a responder pivots metric → log → trace without leaving the page.

---

## Authoring Rules

### Identity and naming

- **Pin the `uid`** deterministically from the service tree: `<platform>-<service>-<purpose>`. Pinned UIDs make re-applies idempotent (no duplicates) and keep alert `__dashboardUid__` references stable.
- Title: `<Service> — <Purpose>` (e.g. `Checkout — RED overview`).
- Experiments: title prefixed `TMP-<initials>-`, throwaway uid, deleted after use.

### Layout

- **RED** (Rate, Errors, Duration) for request-driven views; **USE** (Utilization, Saturation, Errors) for resources.
- First row is always an **overview** answering "is it healthy?" in under 5 seconds — built from **trend panels with semantic thresholds**, not walls of stats/gauges (see Panels). Detail rows below, ordered by triage flow.
- **Narrate with markdown**: the dashboard opens with a text panel stating purpose, audience, and links (runbook, generic dashboard); use text panels to introduce sections where the triage flow isn't obvious from the panels alone.
- One dashboard, one purpose — deep-dive panels go on a separate linked dashboard, not row 12.

### Panels

- Every panel has a **title**, a **description**, and **explicit units** (`reqps`, `ms`, `percentunit` — never default units). The description says what the panel shows, why it matters, and what _bad_ looks like — a responder shouldn't need tribal knowledge to read it.
- **Stats and gauges are earned, not default**: use one only when a single number genuinely _is_ the whole story (time since last backup, days to cert expiry, replicas ready). "Current QPS" / "current CPU" are not — a trend panel carries the same number _plus_ direction and history, at no cost. If the number matters, it matters over time.
- **Semantic color only**: thresholds drive color; red = bad, green = good.
- **Draw alert thresholds on the panels alerts reference** — a responder should see distance-to-alarm, not discover the threshold in the rule definition.
- Legends: template to the distinguishing label only (`{{ status }}`), not the full label set.

### Queries & labels

- PromQL: `$__rate_interval` in `rate()`/`increase()`; rate-then-sum (`sum by (...) (rate(...))`), never `rate(sum(...))`.
- **Aggregate BY the labels you want to see**: `sum by (status) (rate(...))` — never a bare `sum(rate(...))` and never an unaggregated query. Label sets grow over time; an unqualified aggregate silently changes meaning when they do, and an unaggregated one explodes into per-series spaghetti.
- **Bound cardinality**: `topk(10, ...)` (or equivalent) on anything with unbounded label values — a dashboard must survive label growth without becoming unreadable.
- **Percentiles over averages** for latency/duration: p50/p95/p99 via histogram quantiles; an average hides the tail the alert fires on.

### Log panels — the empirical derivation loop (never author from assumptions)

The line stored in the backend is NOT what the app wrote — it has been through stdout wrappers, the collector's relabel/parse stages, label promotion, metadata drops. **You cannot know the deployed shape from source, config, or docs; the store is the only ground truth.** So log panels are DERIVED, per dashboard, by this loop (all steps runnable via the `observability-query` skill):

1. **Sample the store.** Pull 50–100 real lines per stream for the board's service (include an error window if one exists). This is the shape after every wrapper. Source ladder:
   1. the **live store** (gcx / loopback via `observability-query`);
   2. no access? a **local replica of the stack** — the same images + chart values + collector relabel rules + store reproduce the identical pipeline, so locally-derived shapes match prod (k8s + compose planes fully; the cloud host's journal only approximately). A replica also lets you **induce failures safely** to sample error-shaped lines that a healthy prod window never shows;
   3. neither? author from educated defaults but **mark every panel UNVERIFIED** and verify at first deploy.
2. **Probe the query engine — per ENGINE VERSION.** Backends (and their versions) differ in LogQL support — run a stage probe (raw vs `|~` vs `| json` vs `| logfmt` vs `line_format` vs extracted-field filters, comparing row counts) and ship ONLY verified constructs. Proof this matters: a real store returned 0 rows for `line_format` on one engine version and full support on the next — constraints flip with upgrades. Keep the findings in a REPO-LOCAL probe record (deployment-specific by nature — never in the shared standard), and re-probe when the backend image changes.
3. **Map streams by LABEL before parsing bodies.** `sum by (module) (count_over_time({service="x"}[1h]))` — the collector already promoted `module`/`container`/`pod`; labels are free, reliable structure. Split panels by label first; body-parse only when labels can't answer.
4. **Characterize each stream's body format.** One service is often MIXED (e.g. logfmt from one module, JSON from another; JSON plus stray plain lines). Note the level encoding per format: `level=error` (logfmt), `"level":"error"` (zap), `"level":40`/`"severity":"ERROR"` (pino), `⇥error⇥` (tab console), `^E0707` (klog), or none (plain text with `✅`/`Fatal` markers).
5. **Find the noise archetype(s).** The top repetitive low-info lines — gRPC health checks, `/api/status` polls, event-loop stats, reconcile-OK chatter, session scopes — and write a TARGETED negative filter for each (`!= "grpc.health"`, using a negation construct the engine honours — see the constraints table), not a generic one.
6. **Derive the panel list from the service's FAILURE CLASSES — never generic buckets.** A panel named "Errors" or "Logs" is a dump with a filter; a panel is ONE curated question. The question list comes from the service's documented **failure modes and alert sets** (`observability/overview.md` + `alerts/`): each failure class gets an evidence panel whose LogQL matches THAT class's line shapes (found in the step-1 samples), so when its alert fires the panel already shows what happened. Name the panel by the class, not the severity:

   | Archetype             | Curated panel examples (one QUESTION each)                                                                                                                                                   |
   | --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
   | Request server        | "Server errors (5xx)" · "Auth denials (401/403)" · "Slow requests (≥1s)" — each a targeted raw-line regex on the sampled access-log shape                                                    |
   | Reconciler/controller | "Sync/reconcile failures" (the alert-evidence view, module-scoped) · "Git/repo failures" · "Processing timeline" (the work-unit event stream)                                                |
   | Batch/cron            | "Failed runs" (the backup-failed evidence) · "Run outcomes" (completion/summary markers) · full run log (low-volume)                                                                         |
   | Host daemon/journal   | "OOM & kernel crashes" · "Failed systemd units" · "Disk & I/O errors" — one class per panel, mapped to the host alerts; never a full journal stream                                          |
   | Data collector        | "Delivery failures (drops/push errors)" — the send/batch/drop class backing the delivery alerts · "Other collector errors" (the same level match MINUS the delivery class, so nothing hides) |
   | Explorer board        | the one legitimately generic surface: `$service` + `$filter` over volume + errors + all                                                                                                      |

   Two rules make the set complete: **every alert has an evidence panel** (its runbook's "read around the event" view), and **class panels partition the error space** — the last panel is "everything error-level minus the named classes", so an unanticipated failure still surfaces instead of falling between panels. A class panel that's empty on a healthy service is CORRECT (say so in its description).

7. **Compose with the metrics.** A log panel exists to answer "the metric panel beside it went red — what happened?" Place log evidence in the same row as the metric it explains; don't append a generic logs row at the bottom of every board.
8. **Verify, then record.** Run every panel's exact query against the store: it must return REAL rows (or be knowingly empty: quiet service, pre-cutover labels — note which). Record the discovered shapes (format, level encoding, noise filters, engine constraints, probe date) in a REPO-LOCAL probe record so the next author does not re-derive them — and re-probe when they drift. The record is deployment-specific by nature; it never belongs in the shared standard.

**Formatting = REWRITE the line to its key values, NOT pretty-printing.** `prettifyLogMessage` just re-indents the raw JSON blob into a taller blob — same noise, more space; leave it **off**. The tool ladder:

1. **`line_format` (primary, where the engine supports it — probe first):** parse then rewrite — `| json | line_format "{{.level}} {{.msg}}"` renders `info request completed`, the most compact human line. Chain parsers for mixed streams (`| logfmt | json`), use `| regexp` named groups for non-parser formats, `{{if .f}}…{{end}}` for optional fields, TOP-LEVEL fields only. The parsed record stays under the expand arrow (`enableLogDetails: true`).
2. **`options.displayedFields` (fallback when `line_format` is unsupported):** client-side field detection shows `field=value` pairs — better than the blob, more verbose than a rewritten line.
3. **Raw line** for plain-text streams — the line IS the information.

Rules of thumb:

- structured stream → `line_format` on the 2–4 key fields sampled in step 1;
- MIXED stream → chain parsers (or split panels by `module`); a WRONG single parser renders blank lines;
- plain text (restic, journal, klog) → raw line, no parser, no prettify;
- pick the fields from the SAMPLED lines (step 1), not from guesses.

Plus on every logs panel: newest-first, **dedup** on, bounded limit (~100), `showTime`, and the **`$filter` regex variable** applied as `|~ \`$filter\`` so every board is greppable live. Traces: a slow/error-trace table (TraceQL) only once the service emits spans — no dead panels.

### Variables and links

- Template variables: `$landscape` (mandatory) + datasource; label them. Log boards also carry the `$filter` (regex) variable from the logs section above.
- Wire the ecosystem: custom-metric alerts link here via `__dashboardUid__`/`__panelId__`; dashboard links point at `observability/overview.md` (and the relevant `observability/alerts/<slug>/runbook.md`) and the generic dashboard.

### Drill-down — link the boards (don't make responders hunt the folder tree)

Boards must connect, not sit as islands. A responder should click from "something's wrong" straight to the detail:

- **Panel data links.** Any panel that identifies a subject (a service, pod, or trace id) carries a **data link** to the next view — a log line → its trace (datasource `derivedFields`, already wired logs→traces), a status/service tile → that service's `<platform>-<service>-overview`, a trace → its logs. Use `${__value.raw}` / `${__field.labels.<x>}` in the link.
- **Overview → deep-dive.** The platform/overview board links DOWN to each per-service overview — a `dashlist` panel scoped to the Primordial folder, or stat tiles with data links `/d/<platform>-<service>-overview` — and each service overview links to its own deep-dive files. That is the single-pane → drill-in flow; without it, discovery is folder-tree clicking.
- **Carry context across the link.** Pre-fill the target's `$` variables in the link URL (`?var-service=…&var-cluster=…&var-landscape=…`) so the drilled-into board opens already scoped, not reset to defaults.

---

## The Self-Verification Loop

Run for every new or modified dashboard. Sandbox files and the synthetic-data recipe: [sandbox.md](./sandbox.md).

```text
author observability/dashboards/<purpose>.json
   │
   ▼
1. jq empty dashboard.json              # syntax
2. dashboard-linter lint --strict       # best practices — fix or justify every finding
3. docker compose up -d                 # grafana + image-renderer + prometheus
4. promtool tsdb create-blocks-from …   # backfill synthetic series matching the
                                        # dashboard's metric names (real lines, not "No data")
5. curl /render/d/<uid>?kiosk → PNG     # full board + per-panel renders
6. READ the PNGs                        # inspect against the visual checklist
   │
   ├── issues → edit → back to 1
   └── clean → ship
```

**Synthetic data matters**: the TestData datasource cannot run PromQL, so backfill the sandbox Prometheus with series matching every metric the dashboard queries — including error-path series, so thresholds and error panels actually show color.

### Visual checklist ("looks good" defined)

- No "No data" or error panels with synthetic data loaded
- Units render as units (`1.2k req/s`, `250 ms`), not raw numbers
- Y-axes sensible: no clipped peaks, no flat lines from wrong scale
- Legends readable and bounded; panel not swallowed by legend
- Overview row communicates health at a glance
- Thresholds/colors consistent and semantic across all panels
- Grid aligned; renders at 1600px wide with no horizontal scroll
- Every template variable populates and visibly changes the view
