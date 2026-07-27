# Lifecycle framework

The pure, generic reconcile framework every implemented fleet-operator controller
consumes. It lives entirely in the `lib/operator` layer and imports no Kubernetes
package — the architecture gate enforces that — so all of its behaviour is unit
tested at 100% with deterministic, injected dependencies. Controllers own only the
thin adapter that maps API objects onto these types, runs the plan through the
ports, and mirrors the result into status, events, and metrics.

## The three lifecycles, one framework

`lib/operator/lifecycle` holds one framework and three lifecycle planners that
share its deterministic `plan`/result types. Each planner is a pure function from
observed and desired state to a `plan.Plan`; controllers never write a bespoke
reconcile loop.

- **Converge** (`Converge(desired, observed)`) — recompute the full desired state
  every reconcile and diff it against what is observed: create the missing, update
  the drifted, delete the no-longer-desired. When desired and observed already
  match, the plan is empty. This is the healthy-fleet acceptance case.
- **Idempotent-once** (`IdempotentOnce(desired, observed, state)`) — lookup and
  adopt first: when a matching record is observed it plans an adopt, and only when
  none exists does it plan a create. Once terminal success is recorded the
  lifecycle hands off with an empty plan. It never plans a destructive action.
- **Per-version-intent** (`PerVersionIntent(revision, desired, state)`) — each spec
  revision is a distinct intent with its own terminal state. A revision that
  already reached its terminal state plans nothing, so a terminal *failure* never
  retry-storms; a newer revision than the recorded state always starts fresh, so a
  later revision progresses independently of an earlier one — including recovery
  after an earlier failure.

## Deterministic plans

`lib/operator/plan` holds the `Plan` a lifecycle produces: an ordered set of
`Action`s across every target class the fleet touches — `kubernetes`, `vendor`,
`dns`, `secret`, and `git`. Each `Action` records its operation
(`create`/`update`/`delete`/`adopt`), its `Target` (a stable, pointer-only
identity — never a secret value), whether it is destructive, a stable
`DetailsHash` fingerprint of its would-apply content, and safe pointer-only
`Metadata`. Content lives behind the hash so a plan can be logged and compared
without ever carrying a secret.

`plan.Build` places actions into a single canonical order that never depends on
caller insertion order, so two plans over the same actions are equal. A `Plan`
exposes exact counts (`Len`, `Count`), its destructive subset (`Destructive`,
`DestructiveCount`), emptiness (`Empty`), equality and diff (`Equal`, `Diff`), and
human/condition summaries (`HumanSummary`, `ConditionSummary`) — all pure, with no
side effects.

## Two modes, fail-closed

There are exactly two reconcile modes. `Run(ctx, mode, plan, executor)` realizes a
plan:

- **Observe** returns the exact would-apply plan and executes nothing — the plan is
  reported through conditions, metrics, and logs, never a side channel.
- **Active** executes each action in the plan's deterministic order through an
  injected narrow `Executor`, stopping at the first error (no retry-storm) and
  reporting the actions applied so far.

Any other mode fails closed: `Run` executes nothing and returns an error.

## Blast brakes

`lib/operator/brake` holds two independent, typed, chart-configurable caps. Each
returns a freeze-and-page `Decision` (`Writable`/`Freeze`/`Page`, and a
`BlastBrakeTripped` `Condition`) that yields no writable plan when tripped.

- **TrafficPolicy** caps record removal from a traffic set at `CapPercent` per tick
  (pinned default 20%) and refuses to empty a set whose health still passes.
  Boundary ratios are compared with exact integer arithmetic so an at-the-cap ratio
  never rounds up into a trip.
- **DependencyPolicy** caps destructive module operations at `CapModules` per tick
  (pinned default 3).

Both `Validate` their configurable thresholds. The inherited `brake.Evaluate`
percentage entry point is preserved as a compatibility facade over `TrafficPolicy`.

## Condition vocabulary

`lib/operator/conditions` holds the shared, Kubernetes-free condition vocabulary —
every condition the verified plan and gap audit enumerate across the six
implemented controllers — plus stable reason/message derivation primitives
(`New`/`True`/`False`/`Unknown`). Controller adapters translate a `Condition` into a
`metav1.Condition` later. `ModuleSet` provides the per-module isolation contract:
setting a condition on one module never reads or mutates another module's
conditions, and within a module a repeated type is replaced, not duplicated — the
pure core of a map-shaped CR status.

## Deletion-intent vocabulary

`ClassifyDeletion(trigger, class)` in `lib/operator/lifecycle` encodes the
reconciled CR-delete law as pure policy. An ordinary parent-CR deletion retains
(orphans) every stateful realization and never destroys it, while a genuinely
ephemeral class — currently the diskless Dragonfly cache — may be left to ordinary
garbage collection. Spec removal and a typed `Decommission` are the only triggers
that carry a destructive intent; every other path, and any unrecognised trigger,
fails closed to retain. Controller finalizers and concrete resource ownership build
on this policy later.

## Compatibility facade

The new strict lifecycle/plan/brake APIs are authoritative for product paths. The
inherited `plan` and `brake` entry points are preserved additively so the existing
sample controllers and tests keep compiling: `plan.Plan.Empty`, the legacy
condition/status/type symbols (aliased to the shared `conditions` vocabulary), and
`brake.Evaluate`. The compatibility wrappers delegate to the new APIs rather than
duplicate the decisions.
