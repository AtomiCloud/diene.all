// Package plan holds the pure observe-mode planner and the k8s-free condition
// vocabulary. A reconcile computes a Plan (the would-apply diff); the applier
// executes it only in active mode, never in observe mode.
//
// This package is pure domain: it imports no k8s.io/* or sigs.k8s.io/* packages.
package plan

// Condition is a pure, k8s-free condition intent. Adapters translate it into a
// metav1.Condition on the CR status.
type Condition struct {
	Type    string
	Status  string
	Reason  string
	Message string
}

// Standard condition status values.
const (
	StatusTrue  = "True"
	StatusFalse = "False"
)

// Condition type vocabulary preserved verbatim for every consumer (T3 contract).
const (
	TypeReady              = "Ready"
	TypeDrifted            = "Drifted"
	TypeConflict           = "Conflict"
	TypeWaitingForEndpoint = "WaitingForEndpoint"
	TypeBlastBrakeTripped  = "BlastBrakeTripped"
)

// Plan is the would-apply diff a reconcile produces to converge owned resources.
type Plan struct {
	Creates []string
	Deletes []string
}

// Empty reports whether the plan would change nothing (a healthy fleet yields an
// empty plan — the observe-mode acceptance case).
func (p Plan) Empty() bool {
	return len(p.Creates) == 0 && len(p.Deletes) == 0
}
