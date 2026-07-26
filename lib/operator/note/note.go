// Package note holds the pure Note reconcile services: deterministic owned-copy
// naming, payload rendering, and condition derivation. It is the fenced sample
// domain's pure core.
//
// This package is pure domain: it imports no k8s.io/* or sigs.k8s.io/* packages.
// Condition derivation returns the k8s-free plan.Condition; adapters translate it
// into a metav1.Condition on the CR status.
package note

import (
	"fmt"

	"github.com/AtomiCloud/diene.fleet-operator/lib/operator/plan"
)

// ─── DOMAIN WIRING (sample) ──────────────────────────────────────────────────

// Spec is the pure projection of a Note's desired state, decoupled from the API
// types so the domain core never imports k8s.
type Spec struct {
	Title    string
	Body     string
	Category string
	Replicas int32
}

// CopyName is the deterministic owned-ConfigMap name for copy index i. Stable
// names are what make find-or-adopt idempotent (never duplicate-create).
func CopyName(owner string, i int32) string {
	return fmt.Sprintf("%s-copy-%d", owner, i)
}

// Payload renders the owned-ConfigMap body for a spec.
func Payload(spec Spec) string {
	return spec.Title + "\n" + spec.Body
}

// DesiredCopies returns the deterministic set of owned-copy names for a spec.
func DesiredCopies(owner string, spec Spec) []string {
	names := make([]string, 0, spec.Replicas)
	for i := range spec.Replicas {
		names = append(names, CopyName(owner, i))
	}
	return names
}

// ReadyCondition derives the Ready condition from converged vs desired copies.
func ReadyCondition(desired, converged int) plan.Condition {
	if converged >= desired {
		return plan.Condition{
			Type:    plan.TypeReady,
			Status:  plan.StatusTrue,
			Reason:  "Converged",
			Message: fmt.Sprintf("all %d owned copies converged", desired),
		}
	}
	return plan.Condition{
		Type:    plan.TypeReady,
		Status:  plan.StatusFalse,
		Reason:  "Converging",
		Message: fmt.Sprintf("%d of %d owned copies converged", converged, desired),
	}
}

// BrakeCondition derives the BlastBrakeTripped condition from a brake message.
func BrakeCondition(message string) plan.Condition {
	return plan.Condition{
		Type:    plan.TypeBlastBrakeTripped,
		Status:  plan.StatusTrue,
		Reason:  "BlastBrakeTripped",
		Message: message,
	}
}

// ─── END DOMAIN WIRING (sample) ──────────────────────────────────────────────
