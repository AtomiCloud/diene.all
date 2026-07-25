# Contributor Documentation Workflow

Systematically generate contributor documentation for a repository by analyzing git diffs, planning the doc structure, writing files with parallel agents, and auditing the result.

## When to Use

- Running `/contributor-docs`
- Documenting a new repo or feature branch
- Generating technical docs from code changes

## User Entry Points

```
/contributor-docs                    → Analyze current branch vs main, generate docs
/contributor-docs <base-branch>      → Analyze current branch vs specified base
/contributor-docs --phase <phase>    → Skip to a specific phase
```

## Reference Documentation

Knowledge about what contributor docs are, their structure, and formatting rules:

- [What are contributor docs](./index.md)
- [Folder structure](./structure.md)
- [Frontmatter schemas](./frontmatter.md)
- [Formatting checklist](./checklist.md)
- [Classification heuristics](./classification.md)

Skill-internal references (LLM operational instructions):

- [Body templates](./common/templates.md)
- [Writing order](./common/writing-order.md)

## Agent Taxonomy

| Type           | Spawning                        | State transition            | Purpose                               |
| -------------- | ------------------------------- | --------------------------- | ------------------------------------- |
| **Sub-agent**  | `Task` (no team), direct result | No                          | State reads/writes (haiku)            |
| **Team agent** | `Task` (with team), messaging   | Yes — corresponds to a step | Analysis, planning, writing, auditing |

## Orchestrator Model

```
ORCHESTRATOR (you = team lead)
├── SUB-AGENTS (stateless, direct result):
│   ├── plan-state-agent (haiku) — plan phase state reads/writes
│   ├── write-state-agent (haiku) — write phase state reads/writes
│   └── audit-state-agent (haiku) — audit phase state reads/writes
│
├── TEAM AGENTS (spawned via Task tool):
│   ├── diff-analyzer (sonnet) — reads git diff, catalogs all changes
│   ├── doc-planner (opus) — classifies changes, plans doc structure
│   ├── scaffolder (sonnet) — creates all files with frontmatter + TODOs
│   ├── doc-writer (sonnet) ×N — writes one doc file (file-processor loop)
│   ├── big-picture-auditor (opus) — holistic structure and coherence audit
│   └── fact-checker (sonnet) ×N — per-file accuracy audit (file-processor loop)
│
└── State: Per-phase state-agents handle all state writes. Orchestrator NEVER reads/writes JSON directly.
```

**Key principle:** The orchestrator NEVER reads step files directly. Always spawn a team agent and tell it which step file to read and execute.

## Glossary

| Term             | Scope         | Description                                                 |
| ---------------- | ------------- | ----------------------------------------------------------- |
| **Module**       | Doc structure | Bounded context grouping (e.g., `user-management/`)         |
| **Section type** | Doc structure | Content category: feature, concept, algorithm, surface, ADR |
| **Tier**         | Write phase   | Dependency level for writing order (1-6)                    |
| **Doc plan**     | Plan phase    | YAML manifest listing all files to create with metadata     |
| **Scaffold**     | Write phase   | File with frontmatter + TODO notes but no body content      |

## Two-Level State

```
.contributor-docs/
├── task-state.json          # Overall: which phase, base branch, docs root
├── plan-state.json          # Plan phase steps
├── write-state.json         # Write phase steps + tier tracking
├── audit-state.json         # Audit phase steps
├── write-tier-N/            # File-processor state per tier (created during write)
│   ├── state.json
│   └── findings/
├── fact-check/              # File-processor state for audit (created during audit)
│   ├── state.json
│   └── findings/
└── transitions.log          # Append-only step transition log
```

## Task-Level State (`task-state.json`)

| Field          | Type   | Description                                                   |
| -------------- | ------ | ------------------------------------------------------------- |
| `currentPhase` | string | Active phase: `plan`, `write`, `audit`, `completed`, `failed` |
| `baseBranch`   | string | Base branch to diff against (default: `main`)                 |
| `docsRoot`     | string | Output directory (default: `docs/contributor`)                |
| `planFile`     | string | Path to doc plan YAML (`.contributor-docs/doc-plan.yaml`)     |

## Top-Level State Machine

```
task-state.json.currentPhase:
  plan → write → audit → completed
```

### Phase 1: Plan

```
[diff_analysis] → [classify] → [review] → completed
    team(S)         team(O)      inline
```

Dispatch: `plan/PHASE.md`

### Phase 2: Write

```
[scaffold] → [write_tier_1] → [write_tier_2] → ... → [write_tier_6] → completed
  team(S)      file-processor    file-processor         file-processor
                 loop(S)×N         loop(S)×N               loop(S)×N
```

Dispatch: `write/PHASE.md`

### Phase 3: Audit

```
[big_picture] → [fact_check] → completed
    team(O)      file-processor
                   loop(S)×N
```

Dispatch: `audit/PHASE.md`

## Phase Dispatch

**On invocation, spawn a state-agent to assess `task-state.json`, then dispatch:**

| `currentPhase` | Action                                                                  |
| -------------- | ----------------------------------------------------------------------- |
| No state file  | Parse arguments (base branch), create state via state-agent, start Plan |
| `plan`         | Spawn plan state-agent to assess, dispatch per `plan/PHASE.md`          |
| `write`        | Spawn write state-agent to assess, dispatch per `write/PHASE.md`        |
| `audit`        | Spawn audit state-agent to assess, dispatch per `audit/PHASE.md`        |
| `completed`    | Report completion, list generated files                                 |
| `failed`       | Report error, offer retry                                               |

**Transition logging:** When advancing phases, the state-agent appends:

```bash
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) phase-transition from={old_phase} to={new_phase}" >> .contributor-docs/transitions.log
```

## File-Processor Pattern

The write phase (per-tier) and audit fact-check use the file-processor loop. Scripts are in `scripts/`:

```bash
# 1. Initialize: pipe file list into init-state.sh
echo "file1.mdx\nfile2.mdx" | bash docs/standards/contributor-docs/scripts/init-state.sh <state-file> '<source-paths>' <N> '<output-dir>'

# 2. Loop: get next batch, spawn agents, mark done
bash docs/standards/contributor-docs/scripts/next-file.sh <state-file> --batch <N>

# 3. After each agent completes:
bash docs/standards/contributor-docs/scripts/mark-done.sh <state-file> <filename>
```

Progress survives context loss. Re-running resumes from where it left off.

## Rules

### Autonomy

1. Proceed autonomously through diff analysis and classification. Stop at the review gate and wait for user approval.
2. If the plan is rejected, return to classify with user feedback.

### Safety

3. Never overwrite existing documentation files without user confirmation.
4. Never commit generated docs automatically.

### Conventions

5. All generated files must pass [checklist.md](./checklist.md).
6. Follow the tier-based writing order in [writing-order.md](./common/writing-order.md). Never skip tiers.
7. Reference body templates in [templates.md](./common/templates.md) for every file written.

### State

8. Orchestrator NEVER reads/writes state JSON directly — always use state-agents.
9. Team agents NEVER update state — they report back, orchestrator uses state-agents.

## Prerequisites

- Git (for diff analysis)
- `jq` (for file-processor scripts)
- Current branch must have commits ahead of the base branch

## Related Skills

None — this is a standalone documentation generation pipeline.
