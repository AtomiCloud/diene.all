// Package brake holds the pure blast-brake decision: refuse a mass-destructive
// write batch that exceeds a configured percentage-per-tick cap, so a reconcile
// freezes and pages instead of emptying a set while health checks pass.
//
// This package is pure domain: it imports no k8s.io/* or sigs.k8s.io/* packages.
package brake

import "fmt"

// Decision is the blast-brake outcome for a destructive batch.
type Decision struct {
	Tripped bool
	Reason  string
	Message string
}

// Evaluate decides whether deleting deletes out of existing owned resources in a
// single tick exceeds the capPercent cap (0..100). A batch that deletes nothing,
// or one against an empty set, never trips. A capPercent of 0 trips on any
// destructive write; a capPercent of 100 never trips.
func Evaluate(existing, deletes, capPercent int) Decision {
	if deletes <= 0 || existing <= 0 {
		return Decision{}
	}
	// deletes/existing > capPercent/100  <=>  deletes*100 > capPercent*existing
	if deletes*100 > capPercent*existing {
		return Decision{
			Tripped: true,
			Reason:  "BlastBrakeTripped",
			Message: fmt.Sprintf("refusing to delete %d of %d owned resources (cap %d%% per tick)", deletes, existing, capPercent),
		}
	}
	return Decision{}
}
