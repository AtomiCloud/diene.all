# Runbooks and the System Overview

**Every alert has its own runbook, in the same folder as the alert.** The folder structure is the enforcement: a conforming transformer fails an alert set without a `runbook.md`. Shared context lives once in `observability/overview.md` — runbooks link to it instead of repeating it.

```text
observability/
├── overview.md                 # shared system context — written once, linked everywhere
└── alerts/
    └── <alert-slug>/
        ├── critical.yaml       # one file per tier — the filename is the severity
        ├── warning.yaml
        └── runbook.md          # THE runbook for this alert
```

Fill-in templates ship with the `grafana-runbook` skill (`templates/runbook-template.md`, `templates/overview-template.md`).

---

## The System Overview (`observability/overview.md`)

One distilled page of context for the whole repo — what a responder who has never seen this service needs before any runbook makes sense. Structure (all sections required):

| Section              | Content                                                                                                                                                                                               |
| -------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `## What it does`    | One short paragraph, plain language, including who its users are                                                                                                                                      |
| `## How it works`    | The modules and the data flow between them — bullets or a small Mermaid diagram, max ~10 lines                                                                                                        |
| `## Dependencies`    | Table: direction (calls / called-by / stores), system, purpose, what happens here when it fails                                                                                                       |
| `## Failure modes`   | The 2–3 dominant ways this service actually breaks, one line each                                                                                                                                     |
| `## Common commands` | ONE table: kubectl status commands, the 3–5 PromQL queries answering "healthy / loaded / erroring", the LogQL error query, the TraceQL slow-trace query, rollout commands. Placeholders in `{braces}` |
| `## Links`           | Curated dashboard, generic dashboard (LPSM pre-filled URL), deployment, docs/TRD                                                                                                                      |

Keep it distilled: if the overview exceeds a screen, it has stopped being an overview. Commands used by multiple runbooks belong here, not copied into each runbook.

---

## The Per-Alert Runbook (`alerts/<slug>/runbook.md`)

The reader is a half-awake responder. Every step copy-pasteable, every judgment call spelled out. **The canonical fill-in skeleton is the `grafana-runbook` skill's `templates/runbook-template.md`** — the outline below defines the required shape:

````markdown
# <Alert base name>

> Covers: 🚨 <critical name> · ⚠️ <warning name> (whichever tiers exist)
> Context: [System overview](../../overview.md) · [Dashboard panel](url)

<Meaning + user impact — 2 sentences, plain language.>

## Triage

1. <First check — the fastest discriminator:>
   ```bash
   <command>
   ```
   <What the output means. Normal: X. Bad: Y → step N.>

## Remediation

- **<Likely cause 1>**: <fix>. Confirm with: `<command>`
- **<Likely cause 2>**: <fix>. Confirm with: `<command>`

Known cause: YYYY-MM-DD — <one-line incident summary>.

## Escalation

If not resolved in <30m>, or <condition>, escalate to <team/escalation chain> via #<channel>.
Declare an incident if <user-impact condition>.
````

Rules:

- **Triage / Remediation / Escalation are mandatory sections.** A complex, branchy alert may open Triage with a small Mermaid flowchart; simple alerts go straight to numbered steps.
- Every Remediation fix ends with a verification command ("Confirm with: …").
- Commands specific to this alert live here; commands shared across alerts live in the overview's Common commands table — link, don't copy.
- Record past incidents inline (`Known cause: …`) — runbooks are institutional memory, and updating them is a standing post-incident action item.
- A runbook that just restates the alert means the alert fails the actionability gate → back to the alert-set review.

Style: imperative voice; code blocks contain only commands/queries/output; when a step needs judgment, state what GOOD looks like ("normal is <100; >1000 means the consumer is stuck").

---

## Verification

The conforming transformer enforces the folder contract (every alert set has its tier files + `runbook.md` — it fails otherwise). Runbook section completeness and the overview's required sections are PR-review checks.

Then check manually:

- [ ] Every Remediation fix ends with a verification command
- [ ] Any Mermaid parses (paste into mermaid.live)
- [ ] No code block contains prose; all `{placeholders}` filled or intentionally generic
- [ ] The overview still fits on one screen
