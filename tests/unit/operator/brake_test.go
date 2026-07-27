package operator_test

import (
	"testing"

	"github.com/AtomiCloud/diene.fleet-operator/lib/operator/brake"
	"github.com/AtomiCloud/diene.fleet-operator/lib/operator/conditions"
	"github.com/stretchr/testify/require"
)

// ─── Inherited percentage-cap facade (behaviour preserved) ───────────────────

func TestBrakeNoDeletesNeverTrips(t *testing.T) {
	require.False(t, brake.Evaluate(10, 0, 20).Tripped)
}

func TestBrakeEmptySetNeverTrips(t *testing.T) {
	require.False(t, brake.Evaluate(0, 5, 20).Tripped)
}

func TestBrakeUnderCapAllowed(t *testing.T) {
	require.False(t, brake.Evaluate(10, 1, 20).Tripped)
}

func TestBrakeOverCapTrips(t *testing.T) {
	d := brake.Evaluate(10, 5, 20)
	require.True(t, d.Tripped)
	require.Equal(t, "BlastBrakeTripped", d.Reason)
	require.Contains(t, d.Message, "refusing to delete 5 of 10")
}

func TestBrakeZeroCapTripsOnAnyWrite(t *testing.T) {
	require.True(t, brake.Evaluate(10, 1, 0).Tripped)
}

func TestBrakeFullCapNeverTrips(t *testing.T) {
	// existing==deletes at 100% is the exact boundary: it must not trip, and the
	// facade never applies the A-set-empty refusal (no health input).
	require.False(t, brake.Evaluate(10, 10, 100).Tripped)
}

// ─── Decision semantics ──────────────────────────────────────────────────────

func TestDecisionWritableWhenClear(t *testing.T) {
	d := brake.Evaluate(10, 1, 20)
	require.True(t, d.Writable())
	require.False(t, d.Freeze())
	require.False(t, d.Page())
}

func TestDecisionFreezeAndPageWhenTripped(t *testing.T) {
	d := brake.Evaluate(10, 5, 20)
	require.False(t, d.Writable())
	require.True(t, d.Freeze())
	require.True(t, d.Page())
	c := d.Condition()
	require.Equal(t, conditions.TypeBlastBrakeTripped, c.Type)
	require.Equal(t, conditions.StatusTrue, c.Status)
	require.Equal(t, brake.Reason, c.Reason)
}

// ─── Traffic policy ──────────────────────────────────────────────────────────

func TestTrafficPolicyDefaultCap(t *testing.T) {
	require.Equal(t, 20, brake.DefaultTrafficCapPercent)
}

func TestTrafficPolicyValidate(t *testing.T) {
	require.NoError(t, brake.TrafficPolicy{CapPercent: 20}.Validate())
	require.Error(t, brake.TrafficPolicy{CapPercent: -1}.Validate())
	require.Error(t, brake.TrafficPolicy{CapPercent: 101}.Validate())
}

func TestTrafficPolicyBoundaryDoesNotRoundIntoTrip(t *testing.T) {
	p := brake.TrafficPolicy{CapPercent: 20}
	// 2 of 10 == exactly 20% == the cap: it must not trip.
	require.False(t, p.Evaluate(brake.Tick{Existing: 10, Removals: 2}).Tripped)
	// 3 of 10 == 30% > 20%: it trips.
	require.True(t, p.Evaluate(brake.Tick{Existing: 10, Removals: 3}).Tripped)
}

func TestTrafficPolicyRefusesToEmptyHealthySet(t *testing.T) {
	// Under the percentage cap, but emptying a healthy set is always refused.
	d := brake.TrafficPolicy{CapPercent: 100}.Evaluate(brake.Tick{Existing: 4, Removals: 4, Healthy: true})
	require.True(t, d.Tripped)
	require.Contains(t, d.Message, "refusing to empty a healthy set of 4")
}

func TestTrafficPolicyEmptyingUnhealthySetAllowedUnderCap(t *testing.T) {
	// The same emptying is allowed when health does not pass and the cap permits.
	require.False(t, brake.TrafficPolicy{CapPercent: 100}.Evaluate(brake.Tick{Existing: 4, Removals: 4}).Tripped)
}

func TestTrafficPolicyNoOpInputs(t *testing.T) {
	p := brake.TrafficPolicy{CapPercent: 20}
	require.False(t, p.Evaluate(brake.Tick{Existing: 10, Removals: 0, Healthy: true}).Tripped)
	require.False(t, p.Evaluate(brake.Tick{Existing: 0, Removals: 3, Healthy: true}).Tripped)
}

// ─── Dependency policy ───────────────────────────────────────────────────────

func TestDependencyPolicyDefaultCap(t *testing.T) {
	require.Equal(t, 3, brake.DefaultDependencyCapPerTick)
}

func TestDependencyPolicyValidate(t *testing.T) {
	require.NoError(t, brake.DependencyPolicy{CapModules: 3}.Validate())
	require.Error(t, brake.DependencyPolicy{CapModules: -1}.Validate())
}

func TestDependencyPolicyEvaluate(t *testing.T) {
	p := brake.DependencyPolicy{CapModules: 3}
	require.False(t, p.Evaluate(0).Tripped) // no destructive ops
	require.False(t, p.Evaluate(3).Tripped) // at the cap
	d := p.Evaluate(4)                      // over the cap
	require.True(t, d.Tripped)
	require.Contains(t, d.Message, "refusing 4 destructive module operations (cap 3 per tick)")
}
