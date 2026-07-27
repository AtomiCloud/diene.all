// Package plan holds the pure, deterministic would-apply plan the lifecycle
// framework produces and the observe-mode runner consumes. A Plan is an ordered
// set of Actions across every target class the fleet touches (Kubernetes, vendor,
// DNS, secret, Git). Each Action records its operation, target, destructive
// character, a stable details hash, and safe pointer-only metadata — never a
// secret value. A Plan exposes exact counts, its destructive subset, equality and
// diff, emptiness, and human/condition summaries, all without side effects.
//
// This package is pure domain: it imports no k8s.io/* or sigs.k8s.io/* package.
// The condition vocabulary lives in lib/operator/conditions; the symbols re-exported
// here are a compatibility facade for the inherited sample controllers and tests.
package plan

import (
	"fmt"
	"hash/fnv"
	"slices"
	"strconv"
	"strings"

	"github.com/AtomiCloud/diene.fleet-operator/lib/operator/conditions"
)

// ─── Condition-vocabulary compatibility facade ───────────────────────────────
//
// These alias the authoritative vocabulary in lib/operator/conditions so the
// inherited note/journal controllers and their tests keep compiling unchanged.

// Condition is the pure, k8s-free condition intent (aliased to conditions.Condition).
type Condition = conditions.Condition

// Standard condition status values.
const (
	StatusTrue  = conditions.StatusTrue
	StatusFalse = conditions.StatusFalse
)

// Legacy generic condition type vocabulary, preserved for existing consumers.
const (
	TypeReady              = conditions.TypeReady
	TypeDrifted            = conditions.TypeDrifted
	TypeConflict           = conditions.TypeConflict
	TypeWaitingForEndpoint = conditions.TypeWaitingForEndpoint
	TypeBlastBrakeTripped  = conditions.TypeBlastBrakeTripped
)

// ─── The deterministic action plan ───────────────────────────────────────────

// TargetKind names the class of external state an action touches.
type TargetKind string

// Target kinds the fleet operates across.
const (
	TargetKubernetes TargetKind = "kubernetes"
	TargetVendor     TargetKind = "vendor"
	TargetDNS        TargetKind = "dns"
	TargetSecret     TargetKind = "secret"
	TargetGit        TargetKind = "git"
)

// Operation is the verb an action applies to its target.
type Operation string

// Operations a plan can express.
const (
	OpCreate Operation = "create"
	OpUpdate Operation = "update"
	OpDelete Operation = "delete"
	OpAdopt  Operation = "adopt"
)

// Target identifies the thing an action operates on with a stable, pointer-only
// identity — never a secret value.
type Target struct {
	Kind TargetKind
	ID   string
}

// Action is one deterministic step in a Plan. Metadata is safe, pointer-only
// context (identifiers and paths); content lives behind DetailsHash so a Plan can
// be logged and compared without ever carrying a secret value.
type Action struct {
	Op          Operation
	Target      Target
	Destructive bool
	DetailsHash string
	Metadata    map[string]string
}

// Plan is an ordered, deterministic set of would-apply actions.
type Plan struct {
	Actions []Action
}

// HashDetails returns a stable, deterministic hash of the given detail parts. It
// is the canonical way to fill Action.DetailsHash so the same content always
// yields the same hash and the plan carries a fingerprint rather than the value.
func HashDetails(parts ...string) string {
	h := fnv.New64a()
	for _, p := range parts {
		_, _ = h.Write([]byte(p))
		_, _ = h.Write([]byte{0})
	}
	return fmt.Sprintf("%016x", h.Sum64())
}

// Build returns a Plan with the actions placed in a single deterministic order
// (by target kind, operation, target id, then details hash). Ordering never
// depends on caller insertion order, so two plans over the same actions are equal.
func Build(actions []Action) Plan {
	sorted := append([]Action(nil), actions...)
	slices.SortStableFunc(sorted, func(a, b Action) int {
		return strings.Compare(sortKey(a), sortKey(b))
	})
	return Plan{Actions: sorted}
}

func sortKey(a Action) string {
	return string(a.Target.Kind) + "\x00" + string(a.Op) + "\x00" + a.Target.ID + "\x00" + a.DetailsHash
}

// Empty reports whether the plan would change nothing. A healthy fleet yields an
// empty plan — the observe-mode acceptance case.
func (p Plan) Empty() bool {
	return len(p.Actions) == 0
}

// Len returns the number of actions.
func (p Plan) Len() int {
	return len(p.Actions)
}

// Count returns how many actions apply the given operation.
func (p Plan) Count(op Operation) int {
	n := 0
	for _, a := range p.Actions {
		if a.Op == op {
			n++
		}
	}
	return n
}

// Destructive returns the subset of actions marked destructive, preserving plan
// order.
func (p Plan) Destructive() []Action {
	var out []Action
	for _, a := range p.Actions {
		if a.Destructive {
			out = append(out, a)
		}
	}
	return out
}

// DestructiveCount returns how many actions are destructive.
func (p Plan) DestructiveCount() int {
	return len(p.Destructive())
}

// Equal reports whether two plans would apply the same set of actions, regardless
// of the order they were built from.
func (p Plan) Equal(other Plan) bool {
	return p.canonical() == other.canonical()
}

func (p Plan) canonical() string {
	keys := make([]string, 0, len(p.Actions))
	for _, a := range Build(p.Actions).Actions {
		keys = append(keys, sortKey(a)+"\x00"+strconv.FormatBool(a.Destructive))
	}
	return strings.Join(keys, "\n")
}

// Diff compares this plan (treated as desired) against a prior plan and returns
// the actions added (present here, absent there) and removed (present there,
// absent here), each in deterministic order.
func (p Plan) Diff(prior Plan) (added, removed []Action) {
	priorSet := keySet(prior.Actions)
	hereSet := keySet(p.Actions)
	for _, a := range Build(p.Actions).Actions {
		if !priorSet[sortKey(a)] {
			added = append(added, a)
		}
	}
	for _, a := range Build(prior.Actions).Actions {
		if !hereSet[sortKey(a)] {
			removed = append(removed, a)
		}
	}
	return added, removed
}

func keySet(actions []Action) map[string]bool {
	set := make(map[string]bool, len(actions))
	for _, a := range actions {
		set[sortKey(a)] = true
	}
	return set
}

// HumanSummary renders a stable one-line description of the plan for logs.
func (p Plan) HumanSummary() string {
	if p.Empty() {
		return "no changes"
	}
	return fmt.Sprintf("%d actions: %d create, %d update, %d delete, %d adopt (%d destructive)",
		p.Len(), p.Count(OpCreate), p.Count(OpUpdate), p.Count(OpDelete), p.Count(OpAdopt), p.DestructiveCount())
}

// ConditionSummary derives the observe-mode Drifted condition from the plan
// without executing anything: an empty plan is in sync, a non-empty plan reports
// the would-apply counts.
func (p Plan) ConditionSummary() conditions.Condition {
	if p.Empty() {
		return conditions.False(conditions.TypeDrifted, "InSync", "observe mode: healthy fleet, empty plan")
	}
	return conditions.True(conditions.TypeDrifted, "WouldApply",
		fmt.Sprintf("observe mode: would apply %d actions, %d destructive (no writes)", p.Len(), p.DestructiveCount()))
}
