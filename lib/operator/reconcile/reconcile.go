// Package reconcile is the pure application service for the Note domain. It owns
// every domain and application decision — desired content projection, the
// owner-safe diff (create/update/delete + foreign-name conflict), the blast-brake
// decision, observe-mode planning, the durable-ledger transition selection, the
// endpoint-gating (WaitingForEndpoint), and Ready-after-confirm — and returns a
// pure Decision the controller executes. The controller depends only on this
// package (plus the ledger repository and the kube ports); it never imports the
// decision internals (note/plan/brake). The architecture gate enforces that.
//
// This package is pure domain: it imports no k8s.io/* or sigs.k8s.io/* packages.
package reconcile

import (
	"fmt"
	"math"

	"github.com/AtomiCloud/diene.fleet-operator/lib/operator/brake"
	"github.com/AtomiCloud/diene.fleet-operator/lib/operator/ledger"
	"github.com/AtomiCloud/diene.fleet-operator/lib/operator/note"
	"github.com/AtomiCloud/diene.fleet-operator/lib/operator/plan"
)

// Condition re-exports the pure, k8s-free condition type so controllers depend
// only on this service.
type Condition = plan.Condition

// Spec re-exports the pure Note desired state.
type Spec = note.Spec

// Re-exported condition vocabulary so controllers depend only on this service and
// never on the decision internals (the architecture gate enforces that).
const (
	TypeReady              = plan.TypeReady
	TypeDrifted            = plan.TypeDrifted
	TypeConflict           = plan.TypeConflict
	TypeWaitingForEndpoint = plan.TypeWaitingForEndpoint
	TypeBlastBrakeTripped  = plan.TypeBlastBrakeTripped
	StatusTrue             = plan.StatusTrue
	StatusFalse            = plan.StatusFalse
)

// DesiredNames returns the deterministic owned-ConfigMap names for a spec. The
// controller uses it only to address the resource port; the diff decision stays
// in Decide.
func DesiredNames(owner string, spec Spec) []string {
	return note.DesiredCopies(owner, spec)
}

// Kubernetes event types the controller emits.
const (
	EventNormal  = "Normal"
	EventWarning = "Warning"
)

// ReasonOwnedCountOutOfRange is the stable reason for a fail-closed status-count
// conversion. The inherited status facade remains int32, so a count outside that
// representation can never be allowed to accompany writes.
const ReasonOwnedCountOutOfRange = "OwnedCountOutOfRange"

// Event is a reconcile outcome the controller publishes as a Kubernetes event.
type Event struct {
	Type    string
	Reason  string
	Message string
}

// Owned is an owner-UID-verified owned ConfigMap projection.
type Owned struct {
	Name    string
	Payload string
}

// LedgerState projects the durable ledger entry for the Note's coordinate.
type LedgerState struct {
	Exists bool
	Phase  ledger.Phase
}

// LedgerPre is the ledger transition run before resource convergence.
type LedgerPre string

// Ledger pre-actions.
const (
	LedgerPreNone   LedgerPre = "none"
	LedgerPreIntent LedgerPre = "intent"
	LedgerPreAdopt  LedgerPre = "adopt"
)

// Upsert is a desired owned ConfigMap: create it or update it to Payload.
type Upsert struct {
	Name    string
	Payload string
}

// Input is everything the service needs to decide a reconcile.
type Input struct {
	Owner    string
	Spec     Spec
	Existing []Owned  // owner-UID-verified owned ConfigMaps only
	Foreign  []string // desired names held by a non-owned object
	Ledger   LedgerState
	Observe  bool
	BrakeCap int
}

// Limits makes hard representation bounds injectable for a black-box proof while
// production Decide always uses math.MaxInt32. A stricter limit exercises the same
// non-writing path without allocating billions of objects.
type Limits struct {
	OwnedCountMax int
}

// Failure is an explicit, non-writing decision failure.
type Failure struct {
	Reason  string
	Message string
}

// Decision is the pure reconcile plan the controller executes in order.
type Decision struct {
	Write        bool
	LedgerPre    LedgerPre
	Upserts      []Upsert
	Deletes      []string
	ConfirmAfter bool
	Conditions   []Condition
	Events       []Event
	OwnedCount   int32
	Failure      *Failure
}

// Decide computes the reconcile plan for a Note.
func Decide(in Input) Decision {
	return computeDecision(in, Limits{OwnedCountMax: math.MaxInt32})
}

// DecideWithLimits computes the same decision with an explicitly injected owned
// count bound. It exists so the fail-closed narrowing branch is reachable through
// the public black-box API; production callers use Decide's int32 maximum.
func DecideWithLimits(in Input, limits Limits) Decision {
	return computeDecision(in, limits)
}

func computeDecision(in Input, limits Limits) Decision {
	d := Decision{LedgerPre: LedgerPreNone}
	existingCount, err := checkedOwnedCount(len(in.Existing), limits.OwnedCountMax)
	if err != nil {
		return ownedCountFailure(err)
	}

	desiredNames := note.DesiredCopies(in.Owner, in.Spec)
	payload := note.Payload(in.Spec)
	desired := toSet(desiredNames)
	foreign := toSet(in.Foreign)
	ownedPayload := make(map[string]string, len(in.Existing))
	for _, o := range in.Existing {
		ownedPayload[o.Name] = o.Payload
	}

	var upserts []Upsert
	conflict := false
	for _, name := range desiredNames {
		if foreign[name] {
			conflict = true
			continue // never overwrite a foreign object
		}
		if cur, ok := ownedPayload[name]; ok && cur == payload {
			continue // already converged
		}
		upserts = append(upserts, Upsert{Name: name, Payload: payload})
	}

	var deletes []string
	for _, o := range in.Existing {
		if !desired[o.Name] {
			deletes = append(deletes, o.Name)
		}
	}

	if decision := brake.Evaluate(len(in.Existing), len(deletes), in.BrakeCap); decision.Tripped {
		d.Conditions = []Condition{note.BrakeCondition(decision.Message)}
		d.Events = []Event{{EventWarning, "BlastBrakeTripped", decision.Message}}
		d.OwnedCount = existingCount
		return d // freeze, no writes
	}

	if in.Observe {
		// Delegate the observe-mode plan and its condition summary to the generic
		// plan framework rather than duplicate the decision here.
		pl := observePlan(upserts, deletes)
		d.Conditions = []Condition{pl.ConditionSummary()}
		d.OwnedCount = existingCount
		return d
	}

	converged := len(desiredNames) - countMembers(desiredNames, foreign)
	convergedCount, err := checkedOwnedCount(converged, limits.OwnedCountMax)
	if err != nil {
		return ownedCountFailure(err)
	}

	d.Write = true
	d.Upserts = upserts
	d.Deletes = deletes
	d.ConfirmAfter = true
	switch {
	case !in.Ledger.Exists:
		d.LedgerPre = LedgerPreIntent
	case in.Ledger.Phase == ledger.PhaseOrphaned:
		d.LedgerPre = LedgerPreAdopt
	default:
		d.LedgerPre = LedgerPreNone
	}

	d.OwnedCount = convergedCount
	if conflict {
		d.Conditions = []Condition{conflictCondition(), note.ReadyCondition(len(desiredNames), converged)}
		d.Events = []Event{{EventWarning, "OwnedNameCollision", "a desired ConfigMap name is held by a foreign object"}}
		return d
	}
	d.Conditions = []Condition{note.ReadyCondition(len(desiredNames), converged)}
	d.Events = []Event{{EventNormal, "Converged", "note converged to Ready and ledger confirmed"}}
	return d
}

func checkedOwnedCount(n, limit int) (int32, error) {
	if limit < 0 || limit > math.MaxInt32 || n < 0 || n > math.MaxInt32 || n > limit {
		return 0, fmt.Errorf("owned count %d is outside the safe int32 decision range [0,%d]", n, limit)
	}
	return int32(n), nil
}

func ownedCountFailure(err error) Decision {
	message := fmt.Sprintf("reconcile failed closed: %v", err)
	failure := &Failure{Reason: ReasonOwnedCountOutOfRange, Message: message}
	return Decision{
		LedgerPre: LedgerPreNone,
		Failure:   failure,
		Conditions: []Condition{{
			Type:    TypeReady,
			Status:  StatusFalse,
			Reason:  failure.Reason,
			Message: failure.Message,
		}},
		Events: []Event{{EventWarning, failure.Reason, failure.Message}},
	}
}

// WaitingForEndpoint is the condition the controller sets when a durable-ledger
// operation fails (the endpoint is unreachable). It is exported because the
// failure surfaces in the controller's I/O path, not in Decide.
func WaitingForEndpoint(message string) Condition {
	return Condition{Type: plan.TypeWaitingForEndpoint, Status: plan.StatusTrue, Reason: "LedgerUnavailable", Message: message}
}

func conflictCondition() Condition {
	return Condition{Type: plan.TypeConflict, Status: plan.StatusTrue, Reason: "OwnedNameCollision", Message: "a desired ConfigMap name is held by a foreign object"}
}

// observePlan projects the sample reconcile's upserts and deletes onto the generic
// action plan so observe mode reports its would-apply diff through the shared
// framework.
func observePlan(upserts []Upsert, deletes []string) plan.Plan {
	actions := make([]plan.Action, 0, len(upserts)+len(deletes))
	for _, u := range upserts {
		actions = append(actions, plan.Action{
			Op:     plan.OpCreate,
			Target: plan.Target{Kind: plan.TargetKubernetes, ID: u.Name},
		})
	}
	for _, name := range deletes {
		actions = append(actions, plan.Action{
			Op:          plan.OpDelete,
			Target:      plan.Target{Kind: plan.TargetKubernetes, ID: name},
			Destructive: true,
		})
	}
	return plan.Build(actions)
}

func toSet(values []string) map[string]bool {
	set := make(map[string]bool, len(values))
	for _, v := range values {
		set[v] = true
	}
	return set
}

func countMembers(names []string, set map[string]bool) int {
	n := 0
	for _, name := range names {
		if set[name] {
			n++
		}
	}
	return n
}
