package operator_test

import (
	"testing"

	"github.com/AtomiCloud/diene.go-base/lib/operator/ledger"
	"github.com/AtomiCloud/diene.go-base/lib/operator/plan"
	"github.com/AtomiCloud/diene.go-base/lib/operator/reconcile"
	"github.com/stretchr/testify/require"
)

func spec(replicas int32) reconcile.Spec {
	return reconcile.Spec{Title: "T", Body: "B", Category: "work", Replicas: replicas}
}

func payload() string { return "T\nB" }

func condition(conds []reconcile.Condition, typ string) *reconcile.Condition {
	for i := range conds {
		if conds[i].Type == typ {
			return &conds[i]
		}
	}
	return nil
}

func TestDecideConvergeFresh(t *testing.T) {
	d := reconcile.Decide(reconcile.Input{Owner: "n", Spec: spec(2), BrakeCap: 20})
	require.True(t, d.Write)
	require.Equal(t, reconcile.LedgerPreIntent, d.LedgerPre)
	require.True(t, d.ConfirmAfter)
	require.Len(t, d.Upserts, 2)
	require.Equal(t, int32(2), d.OwnedCount)
	ready := condition(d.Conditions, plan.TypeReady)
	require.NotNil(t, ready)
	require.Equal(t, plan.StatusTrue, ready.Status)
}

func TestDecideContentUpdate(t *testing.T) {
	d := reconcile.Decide(reconcile.Input{
		Owner:    "n",
		Spec:     spec(1),
		Existing: []reconcile.Owned{{Name: "n-copy-0", Payload: "stale"}},
		Ledger:   reconcile.LedgerState{Exists: true, Phase: ledger.PhaseConfirmed},
		BrakeCap: 20,
	})
	require.Equal(t, reconcile.LedgerPreNone, d.LedgerPre)
	require.Len(t, d.Upserts, 1)
	require.Equal(t, payload(), d.Upserts[0].Payload)
}

func TestDecideNoChange(t *testing.T) {
	d := reconcile.Decide(reconcile.Input{
		Owner:    "n",
		Spec:     spec(1),
		Existing: []reconcile.Owned{{Name: "n-copy-0", Payload: payload()}},
		Ledger:   reconcile.LedgerState{Exists: true, Phase: ledger.PhaseConfirmed},
		BrakeCap: 20,
	})
	require.Empty(t, d.Upserts)
	require.Empty(t, d.Deletes)
}

func TestDecideDeleteUnderCap(t *testing.T) {
	d := reconcile.Decide(reconcile.Input{
		Owner:    "n",
		Spec:     spec(1),
		Existing: []reconcile.Owned{{Name: "n-copy-0", Payload: payload()}, {Name: "n-copy-1", Payload: payload()}},
		Ledger:   reconcile.LedgerState{Exists: true, Phase: ledger.PhaseConfirmed},
		BrakeCap: 100,
	})
	require.Equal(t, []string{"n-copy-1"}, d.Deletes)
}

func TestDecideBrakeTrips(t *testing.T) {
	existing := []reconcile.Owned{
		{Name: "n-copy-0", Payload: payload()},
		{Name: "n-copy-1", Payload: payload()},
		{Name: "n-copy-2", Payload: payload()},
		{Name: "n-copy-3", Payload: payload()},
	}
	d := reconcile.Decide(reconcile.Input{Owner: "n", Spec: spec(1), Existing: existing, BrakeCap: 20})
	require.False(t, d.Write)
	require.NotNil(t, condition(d.Conditions, plan.TypeBlastBrakeTripped))
	require.Equal(t, int32(4), d.OwnedCount)
}

func TestDecideObserveDrift(t *testing.T) {
	d := reconcile.Decide(reconcile.Input{Owner: "n", Spec: spec(2), Observe: true, BrakeCap: 20})
	require.False(t, d.Write)
	drift := condition(d.Conditions, plan.TypeDrifted)
	require.NotNil(t, drift)
	require.Equal(t, plan.StatusTrue, drift.Status)
}

func TestDecideObserveInSync(t *testing.T) {
	d := reconcile.Decide(reconcile.Input{
		Owner:    "n",
		Spec:     spec(1),
		Existing: []reconcile.Owned{{Name: "n-copy-0", Payload: payload()}},
		Observe:  true,
		BrakeCap: 20,
	})
	drift := condition(d.Conditions, plan.TypeDrifted)
	require.NotNil(t, drift)
	require.Equal(t, plan.StatusFalse, drift.Status)
}

func TestDecideAdoptOrphaned(t *testing.T) {
	d := reconcile.Decide(reconcile.Input{
		Owner:    "n",
		Spec:     spec(1),
		Ledger:   reconcile.LedgerState{Exists: true, Phase: ledger.PhaseOrphaned},
		BrakeCap: 20,
	})
	require.Equal(t, reconcile.LedgerPreAdopt, d.LedgerPre)
}

func TestDecideConflict(t *testing.T) {
	d := reconcile.Decide(reconcile.Input{
		Owner:    "n",
		Spec:     spec(1),
		Foreign:  []string{"n-copy-0"},
		BrakeCap: 20,
	})
	require.Empty(t, d.Upserts) // never overwrite the foreign object
	require.NotNil(t, condition(d.Conditions, plan.TypeConflict))
	ready := condition(d.Conditions, plan.TypeReady)
	require.NotNil(t, ready)
	require.Equal(t, plan.StatusFalse, ready.Status)
	require.Equal(t, int32(0), d.OwnedCount)
}

func TestDesiredNames(t *testing.T) {
	require.Equal(t, []string{"n-copy-0", "n-copy-1"}, reconcile.DesiredNames("n", spec(2)))
}

func TestWaitingForEndpointCondition(t *testing.T) {
	c := reconcile.WaitingForEndpoint("dial tcp: connection refused")
	require.Equal(t, plan.TypeWaitingForEndpoint, c.Type)
	require.Equal(t, plan.StatusTrue, c.Status)
	require.Contains(t, c.Message, "connection refused")
}
