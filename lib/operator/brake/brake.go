// Package brake holds the pure blast-brake policies. Two independent, typed caps
// guard mass-destructive reconciles: a traffic percentage cap (default 20% of a
// set removed per tick, and never emptying a healthy A-set), and a dependency
// absolute cap (default 3 destructive modules per tick). A tripped brake returns a
// freeze-and-page decision with no writable plan; the reconcile writes nothing.
//
// This package is pure domain: it imports no k8s.io/* or sigs.k8s.io/* package.
package brake

import (
	"fmt"

	"github.com/AtomiCloud/diene.fleet-operator/lib/operator/conditions"
)

// Pinned default caps. The chart may override them; Validate bounds the override.
const (
	DefaultTrafficCapPercent    = 20
	DefaultDependencyCapPerTick = 3
)

// Reason is the stable reason string a tripped brake reports.
const Reason = "BlastBrakeTripped"

// Decision is a blast-brake outcome. A tripped decision freezes the reconcile and
// pages; it is never writable.
type Decision struct {
	Tripped bool
	Reason  string
	Message string
}

// tripped builds a frozen, paging decision with a stable reason.
func tripped(message string) Decision {
	return Decision{Tripped: true, Reason: Reason, Message: message}
}

// Writable reports whether a reconcile may apply writes under this decision. A
// tripped decision is a freeze-and-page and is never writable.
func (d Decision) Writable() bool {
	return !d.Tripped
}

// Freeze reports whether the reconcile must freeze (alias of Tripped, named for
// the freeze-and-page semantics at the call site).
func (d Decision) Freeze() bool {
	return d.Tripped
}

// Page reports whether the trip must page an operator.
func (d Decision) Page() bool {
	return d.Tripped
}

// Condition derives the BlastBrakeTripped condition for a tripped decision.
func (d Decision) Condition() conditions.Condition {
	return conditions.True(conditions.TypeBlastBrakeTripped, Reason, d.Message)
}

// TrafficPolicy caps record-removal from a traffic set at CapPercent per tick and
// refuses to empty a set whose health still passes.
type TrafficPolicy struct {
	CapPercent int
}

// Validate bounds the configurable percentage cap to [0, 100].
func (p TrafficPolicy) Validate() error {
	if p.CapPercent < 0 || p.CapPercent > 100 {
		return fmt.Errorf("brake: traffic cap percent %d out of range [0,100]", p.CapPercent)
	}
	return nil
}

// Tick describes one traffic reconcile's removal proposal: the current set size,
// how many records it would remove, and whether the set's health checks pass.
type Tick struct {
	Existing int
	Removals int
	Healthy  bool
}

// Evaluate decides whether a tick's removals trip the brake. It validates both
// policy and proposal at the decision boundary: negative sizes, removals above the
// existing set, and invalid caps all freeze and page. Emptying the whole set while
// healthy always trips (the A-set-empty refusal), independent of the percentage.
// Otherwise it compares removals/existing to CapPercent without multiplication
// overflow, while preserving the exact at-cap boundary.
func (p TrafficPolicy) Evaluate(tick Tick) Decision {
	if err := p.Validate(); err != nil {
		return tripped(fmt.Sprintf("invalid traffic brake policy: %v", err))
	}
	if tick.Existing < 0 || tick.Removals < 0 {
		return tripped(fmt.Sprintf("invalid traffic removal proposal: existing=%d removals=%d must be non-negative", tick.Existing, tick.Removals))
	}
	if tick.Removals > tick.Existing {
		return tripped(fmt.Sprintf("invalid traffic removal proposal: removals %d exceed existing %d", tick.Removals, tick.Existing))
	}
	if tick.Removals == 0 {
		return Decision{}
	}
	if tick.Healthy && tick.Removals == tick.Existing {
		return tripped(fmt.Sprintf("refusing to empty a healthy set of %d records", tick.Existing))
	}
	// floor(cap*existing/100) is calculated without forming cap*existing:
	// cap*(existing/100) cannot exceed existing, and cap*(existing%100) is
	// bounded by 9,900. For integer removals, removals > floor(product/100)
	// is exactly equivalent to removals*100 > cap*existing.
	wholeHundreds := tick.Existing / 100
	remainder := tick.Existing % 100
	allowed := p.CapPercent*wholeHundreds + p.CapPercent*remainder/100
	if tick.Removals > allowed {
		return tripped(fmt.Sprintf("refusing to delete %d of %d owned resources (cap %d%% per tick)", tick.Removals, tick.Existing, p.CapPercent))
	}
	return Decision{}
}

// DependencyPolicy caps the number of destructive module operations at CapModules
// per tick.
type DependencyPolicy struct {
	CapModules int
}

// Validate rejects a negative cap.
func (p DependencyPolicy) Validate() error {
	if p.CapModules < 0 {
		return fmt.Errorf("brake: dependency cap %d must not be negative", p.CapModules)
	}
	return nil
}

// Evaluate trips when the number of destructive module operations this tick
// exceeds CapModules. It validates both the policy and count at the decision
// boundary; an invalid cap or negative count freezes and pages.
func (p DependencyPolicy) Evaluate(destructive int) Decision {
	if err := p.Validate(); err != nil {
		return tripped(fmt.Sprintf("invalid dependency brake policy: %v", err))
	}
	if destructive < 0 {
		return tripped(fmt.Sprintf("invalid destructive module count %d: must be non-negative", destructive))
	}
	if destructive == 0 {
		return Decision{}
	}
	if destructive > p.CapModules {
		return tripped(fmt.Sprintf("refusing %d destructive module operations (cap %d per tick)", destructive, p.CapModules))
	}
	return Decision{}
}

// Evaluate is the inherited percentage-cap entry point, preserved as a
// compatibility facade over TrafficPolicy. It carries no A-set health input, so it
// never applies the healthy-set-empty refusal. Its signature and valid-input
// behavior remain compatible while invalid proposals now fail closed.
func Evaluate(existing, deletes, capPercent int) Decision {
	return TrafficPolicy{CapPercent: capPercent}.Evaluate(Tick{Existing: existing, Removals: deletes})
}
