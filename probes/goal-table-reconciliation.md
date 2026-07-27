# go-consumer probe matrix — 1:1 reconciliation against the goal's Features table

Chain-side conductor material, not a CyanPrint feature row. It exists so a future
auditor reads an **explained** delta rather than re-deriving one.

Compared: `goals/go-consumer.md` § "Features (= probe matrix)" against this branch's
`probes/features.json` and `probes/*.ts`.

## Totals

| quantity                                                 | count                       |
| -------------------------------------------------------- | --------------------------- |
| inherited rows at the parent (`go-base-w-observability`) | 67                          |
| inherited rows REMOVED here                              | 1 (`sample-domain-journey`) |
| own `diene/go-consumer` rows ADDED                       | 25                          |
| **rows in `probes/features.json`**                       | **91**                      |

`67 − 1 + 25 = 91`. Every row has exactly one `probes/<row>.ts`, and every
`probes/*.ts` has exactly one row — verified bidirectionally, in both directions,
not just the easy one.

## Own rows — goal entry ↔ `features.json` row, 1:1

The goal names 25 own mechanisms. All 25 are present with the goal's class.

### Gates (11 — each `proven` + exactly ONE meaningful sabotage)

| goal entry              | `features.json` name      | class | cost class         |
| ----------------------- | ------------------------- | ----- | ------------------ |
| worker-mode SIT         | `worker-mode-sit`         | gate  | heavy · serialized |
| db-init-mode SIT        | `db-init-mode-sit`        | gate  | heavy · serialized |
| db-init idempotency SIT | `db-init-idempotency-sit` | gate  | heavy · serialized |
| message journey SIT     | `message-journey-sit`     | gate  | heavy · serialized |
| OTEL export SIT         | `otel-export-sit`         | gate  | heavy · serialized |
| app-chart lint          | `app-chart-lint`          | gate  | light              |
| primordial-chart lint   | `primordial-chart-lint`   | gate  | light              |
| config layering         | `config-layering`         | gate  | medium             |
| config schema gen-check | `config-schema-gen-check` | gate  | medium             |
| constants-sync hook     | `constants-sync-lint`     | gate  | light              |
| rebrand static guard    | `rebrand-static-guard`    | gate  | light              |

### Smokes (11 — proven-only, NO sabotage)

| goal entry                      | `features.json` name        | class | cost class         |
| ------------------------------- | --------------------------- | ----- | ------------------ |
| cmd entry                       | `cmd-entry`                 | smoke | medium             |
| env override convention         | `env-override-convention`   | smoke | heavy · serialized |
| health metric                   | `health-metric`             | smoke | heavy · serialized |
| HttpClient/AuthClient/Encryptor | `http-auth-encryptor`       | smoke | medium             |
| health subcommand               | `health-subcommand`         | smoke | heavy · serialized |
| task surface                    | `task-surface`              | smoke | heavy · serialized |
| secret behavior                 | `secret-behavior`           | smoke | heavy · serialized |
| app-chart template              | `app-chart-template`        | smoke | light              |
| primordial-chart template       | `primordial-chart-template` | smoke | light              |
| app-chart install               | `app-chart-install`         | smoke | heavy              |
| primordial-chart install        | `primordial-chart-install`  | smoke | heavy              |

### Presence (3 — exists-only)

| goal entry                   | `features.json` name                                                | class    | cost class |
| ---------------------------- | ------------------------------------------------------------------- | -------- | ---------- |
| `config/dev.yaml`            | `config-dev-yaml`                                                   | presence | light      |
| service-tree `app:` block    | `service-tree-app-block`                                            | presence | light      |
| observability standards      | inherited `observability-standards-present` (`diene/observability`) | presence | light      |
| — (see SANCTIONED ADD below) | `lib-dogfood-artifacts`                                             | presence | light      |

The goal's third presence bullet — **observability standards** — is NOT an own row:
it arrives through the `observability` payload branch as
`observability-standards-present` under `template: diene/observability` and is
re-probed here by inheritance. Authoring a second copy under
`template: diene/go-consumer` would duplicate one mechanism across two rows, which
S26 forbids (one row per independently invoked mechanism). This is why the own-row
count is 25 with `lib-dogfood-artifacts` in the third presence slot rather than 26.

### Naming deviation (not a matrix delta)

`cmd-entry` where bun-consumer has `commander-entry`. The goal names the feature
"cmd entry", and Go dispatch is **cobra**, not commander. Same mechanism, same
class, one row; only the row's name differs, so the matrix is still 1:1.

## The two SANCTIONED deltas

Both are LEAD-APPROVED (lead ruling relayed by noel, recorded no later than the
machine-stamped diary row `2026-07-26T22:18:50.704Z` that closed it).

### 1. REMOVED — `sample-domain-journey` (smoke, `diene/go-base`) — **SANCTIONED**

The goal's sanctioned fenced swap replaces the go-base sample domain **wholesale**
and deletes its invocation path `scripts/validate/sample-journey.sh` along with it.
The goal's own inherited-smoke list does not name the row.

A smoke whose invocation path the goal itself deletes has exactly two possible
outcomes, and both are wrong:

- it fails for a **non-product reason** (a missing script is not a product defect,
  and a red row that is not a real defect trains readers to discount red); or
- it is **skipped silently** — which is the looks-present-asserts-nothing failure
  class, the worse of the two, because the matrix still reads as covering it.

Coverage does not disappear; it MOVES to mechanisms that do exist here:
`worker-mode-sit` and `db-init-mode-sit` (the compiled artifact driven end to end
against real dependencies) plus the `task-surface` smoke (the local operations the
old journey script wrapped). Verified: the deleted subject is confirmed gone from
this branch (`scripts/validate/sample-journey.sh` deleted, `probes/sample-domain-journey.ts`
deleted, and its `features.json` row removed), and `probes/go-typecheck.ts`'s
`expectedImpact` list — which named the removed row — was repointed at the consumer
rows a Go type error legitimately reddens. A dangling `expectedImpact` entry is not
inert: under PROBES Gap 6 the engine consults that set when attributing a
legitimately-reddened co-selected control, so a name that can never match is a
latent mis-attribution.

### 2. ADDED — `lib-dogfood-artifacts` (presence, `diene/go-consumer`) — **SANCTIONED**

Three independent reasons, any one of which would justify it:

- the goal's **Purpose** mandates mirroring bun-consumer **1:1 in SHAPE**;
- **bun-consumer ships exactly this row** (`probes/lib-dogfood-artifacts.ts`), so
  omitting it would BREAK that 1:1 shape;
- this node carries the transferred **R-E12 go-family dogfood obligation** (stamped
  onto the node diary `2026-07-25T20:41:40.365Z`, re-stamped
  `2026-07-26T21:54:57.506Z`), which otherwise has **no standing gate** anywhere —
  the obligation would be asserted by nothing.

**Binding lead condition on this row, and how it is met.** It must assert on VALUES,
never on exit 0; it must PRINT the artifacts and their COUNT; and it must FAIL when
a count is zero. A presence check that passes on an empty result set is the exact
trap that let a 23/23 green run prove retracted bytes on another node.

The row prints and then compares three numbers **twice** — once inside the
dev-shell script (so the values land in the run's own transcript as attributable
evidence) and once in the probe body against that printed summary (so the row cannot
pass if the script's guards are weakened or removed):

```
9 module requires · 0 replaces · 9 vendored usage skills
```

Measured on this branch: 9 / 0 / 9, with all nine requires pinned to published
release versions and each having its own vendored usage skill. The fail-on-zero
guard was verified by CONTROL, not by reading it: run against a synthetic empty tree
(bare `go.mod`, empty vendor directory) the same script exits **1** with
`❌ ZERO diene Go module requires`, rather than passing on the empty scan.

`replace` count is read with `go mod edit -json | jq '.Replace | length'` — a
structured query, never `grep go.mod`, because a commented-out or block-formatted
`replace` would fool a text search and a parser cannot be fooled by formatting.

## Deliberately NOT rows (S27 conductor boundary)

Named here so a future auditor does not read their absence as a gap. Each is
conductor-sweep machinery, never a shipped probe row:

- deadcode no-exclusions verification;
- absence of in-repo library copies (source-purity);
- observability payload / add-back exactness;
- fenced-swap purity;
- parent merge and topology assertions;
- strip-completeness.

The goal states this directly, and PROBES §2.10 generalizes it: a semantic validator
that positively parses and enforces a rule may be a gate, but a standalone
"find no X" search may not.

## Vacuity audit — caught-positive but blind to a MISSING subject

A gate can be caught-positive on its declared sabotage and still vacuous on a
different axis: printing a count is not the same as REFUSING a zero count. Every own
row was therefore asked two questions, not one — does the sabotage redden it, AND
does it refuse to judge when its subject is missing or empty.

**Closed inside this suite** (each refuses an empty/missing subject explicitly):

| row                                                | zero-subject refusal                                                                                                                   |
| -------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `lib-dogfood-artifacts`                            | refuses 0 requires and 0 skills, twice over; verified by empty-tree control                                                            |
| `config-dev-yaml`                                  | refuses 0 resolved keys; requires all 10 keys its scripts dereference                                                                  |
| `service-tree-app-block`                           | refuses 0 layers and 0 resolved fields                                                                                                 |
| `constants-sync-lint`                              | refuses a 0-vs-0 comparison (an empty key set trivially equals an empty constant set)                                                  |
| `config-schema-gen-check`                          | refuses the empty-string sha256 on either side of the digest comparison                                                                |
| `rebrand-static-guard`                             | refuses 0 identity values, 0 config files, or 0 shipped Go files                                                                       |
| `app-chart-template` / `primordial-chart-template` | refuse a render with 0 documents or 0 kinds                                                                                            |
| `app-chart-lint` / `primordial-chart-lint`         | require the printed `1 chart(s) linted, 0 chart(s) failed`                                                                             |
| `cmd-entry`                                        | requires exactly 1 `main` package and each subcommand listed AND invoked                                                               |
| `http-auth-encryptor`                              | refuses `no tests to run` / 0 PASS lines; requires all three named seams among what ran                                                |
| all nine SIT rows                                  | refuse `no tests to run` and require the selected journey's NAME in the transcript, because `go test -run` matching zero tests exits 0 |
| `config-layering`                                  | refuses a fixture with fewer than 2 layers, and requires the red branch to fail for a VALIDATION reason                                |
| `task-surface`                                     | asserts container counts before and after teardown, so `up`/`down` must have done something                                            |
| chart install rows                                 | refuse 0 CRD fixtures, 0 vendored files, <2 releases, 0 T3 CRs                                                                         |

**Open, owned elsewhere — reported, not silently absorbed:**

- None outstanding in the three gate scripts owned by the Go worker. The
  vacuity the controller found in `scripts/validate/constants-sync.sh` (an app-only
  settings tree plus an empty `constants.go` printed `0 config keys, 0 constants,
0 unmatched` and exited 0) has LANDED as fixed: all three scripts now carry
  explicit refuse-on-empty guards. Verified by running them, not by reading the
  diff: `5 config keys, 5 constants, 0 unmatched`; matching sha256 digests on both
  sides of the schema comparison; `17 identity/auth values from 3 config files,
23 shipped Go files, 0 hardcoded`.

## Probe-speed compliance (PROBES §5)

| cost class | rows | budget                  |
| ---------- | ---- | ----------------------- |
| light      | 8    | <30s                    |
| medium     | 4    | <3min                   |
| heavy      | 13   | build / stack / cluster |

Median own-row cost is dominated by the SIT and install rows, which is intrinsic to
this node rather than an authoring defect: the goal's own DoD requires the **compiled
binary** driven against **real dependencies** for nine mechanisms, and R20 requires
both charts installed into a real cluster. Each heavy row's file states why a lighter
proxy cannot prove the same mechanism.

Two serialization facts the venue must honour:

- **The nine SIT rows and `task-surface` share ONE host `mkdir` spinlock** and must
  run at parallel 1 relative to each other. The local stack binds the FIXED host
  ports in `config/dev.yaml`, so per-invocation uniqueness is genuinely impractical
  and PROBES §5 permits a declared serialization requirement instead.
- **The two chart-install rows derive a UNIQUE per-invocation k3d cluster name** and
  pin every `kubectl`/`helm` call to that cluster's context. A fixed name collides
  under parallelism and cascades a healthy-control failure into a whole-suite fold —
  one fixed k3d name folded 140/141 rows on operator-template.

## Gap-5 sweep (PROBES Gap 5)

`sandbox: {snapshot: 'git'}` constructs the run repository with **no SCM remote**, so
a gate consulting the remote passes on a direct checkout and fails in the sandbox.
The mitigation was applied by sweeping EVERY sandbox-constructing helper on this
branch, not just one:

- `probes/lib/consumer-sit.ts` — `git remote add origin <url>` if absent;
- `probes/lib/sandbox-script.ts` — the same preamble, shared by `chart-install`,
  `task-surface`, `cmd-entry`, `config-layering`, `http-auth-encryptor`,
  `lib-dogfood-artifacts`, `config-dev-yaml`, and `service-tree-app-block`.

The URL is added as remote METADATA only; nothing fetches from it. This is
gate-environment setup, not a law weakening — the property under test is chart/config
validity and buildability, never remote presence.
