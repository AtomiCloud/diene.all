package operator_test

import (
	"context"
	"errors"
	"testing"

	"github.com/AtomiCloud/diene.fleet-operator/lib/operator/lifecycle"
	"github.com/AtomiCloud/diene.fleet-operator/lib/operator/plan"
	"github.com/stretchr/testify/require"
)

// item builds a lifecycle Item for tests.
func item(key, hash string) lifecycle.Item {
	return lifecycle.Item{
		Key:         key,
		DetailsHash: hash,
		Target:      plan.Target{Kind: plan.TargetVendor, ID: key},
		Destructive: true,
	}
}

// fakeExecutor records executed actions and can fail on a chosen target id.
type fakeExecutor struct {
	failOn   string
	executed []plan.Action
}

func (f *fakeExecutor) Execute(_ context.Context, action plan.Action) error {
	if action.Target.ID == f.failOn {
		return errors.New("boom")
	}
	f.executed = append(f.executed, action)
	return nil
}

type valueExecutor struct{}

func (valueExecutor) Execute(_ context.Context, _ plan.Action) error {
	return nil
}

type metadataMutatingExecutor struct {
	replacement plan.Reference
	seen        []plan.Reference
}

func (f *metadataMutatingExecutor) Execute(_ context.Context, action plan.Action) error {
	f.seen = append(f.seen, action.Metadata["credential"])
	action.Metadata["credential"] = f.replacement
	action.Metadata["injected"] = f.replacement
	return nil
}

// ─── Mode ────────────────────────────────────────────────────────────────────

func TestModeValid(t *testing.T) {
	require.True(t, lifecycle.ModeObserve.Valid())
	require.True(t, lifecycle.ModeActive.Valid())
	require.False(t, lifecycle.Mode("audit").Valid())
}

// ─── Converge ────────────────────────────────────────────────────────────────

func TestConvergeCreatesUpdatesDeletes(t *testing.T) {
	// Arrange: "keep" is in sync, "drift" changed, "new" is missing, "stale" is gone.
	desired := []lifecycle.Item{item("keep", "h1"), item("drift", "h2new"), item("new", "h3")}
	observed := []lifecycle.Item{item("keep", "h1"), item("drift", "h2old"), item("stale", "h9")}
	// Act
	p := lifecycle.Converge(desired, observed)
	// Assert: one create, one update, one delete; the in-sync item yields nothing.
	require.Equal(t, 1, p.Count(plan.OpCreate))
	require.Equal(t, 1, p.Count(plan.OpUpdate))
	require.Equal(t, 1, p.Count(plan.OpDelete))
	require.Equal(t, 3, p.Len())
}

func TestConvergeHealthyFleetIsEmpty(t *testing.T) {
	same := []lifecycle.Item{item("a", "h"), item("b", "h")}
	require.True(t, lifecycle.Converge(same, same).Empty())
}

func TestConvergeDuplicateDesiredKeyLastWins(t *testing.T) {
	// Arrange: a duplicate desired key; the later hash wins and the key is not
	// planned twice.
	desired := []lifecycle.Item{item("k", "old"), item("k", "new")}
	// Act
	p := lifecycle.Converge(desired, nil)
	// Assert
	require.Equal(t, 1, p.Len())
	require.Equal(t, plan.OpCreate, p.Actions[0].Op)
	require.Equal(t, "new", p.Actions[0].DetailsHash)
}

// ─── Idempotent-once ─────────────────────────────────────────────────────────

func TestIdempotentOnceHandsOffAfterTerminal(t *testing.T) {
	p := lifecycle.IdempotentOnce(item("t", "h"), nil, lifecycle.OnceState{Terminal: true})
	require.True(t, p.Empty())
}

func TestIdempotentOnceAdoptsExisting(t *testing.T) {
	found := item("t", "h")
	p := lifecycle.IdempotentOnce(item("t", "h"), &found, lifecycle.OnceState{})
	require.Equal(t, 1, p.Len())
	require.Equal(t, plan.OpAdopt, p.Actions[0].Op)
}

func TestIdempotentOnceCreatesWhenAbsent(t *testing.T) {
	p := lifecycle.IdempotentOnce(item("t", "h"), nil, lifecycle.OnceState{})
	require.Equal(t, 1, p.Len())
	require.Equal(t, plan.OpCreate, p.Actions[0].Op)
}

// ─── Per-version-intent ──────────────────────────────────────────────────────

func TestPerVersionNewRevisionStartsFresh(t *testing.T) {
	// A newer spec revision than the recorded state starts fresh.
	p := lifecycle.PerVersionIntent("rev2", item("cf", "h"), lifecycle.IntentState{Revision: "rev1", Terminal: true})
	require.Equal(t, 1, p.Len())
	require.Equal(t, plan.OpCreate, p.Actions[0].Op)
}

func TestPerVersionTerminalRevisionPlansNothing(t *testing.T) {
	p := lifecycle.PerVersionIntent("rev1", item("cf", "h"), lifecycle.IntentState{Revision: "rev1", Terminal: true})
	require.True(t, p.Empty())
}

func TestPerVersionTerminalFailureDoesNotRetryStorm(t *testing.T) {
	// A terminally failed revision plans nothing until a new revision arrives.
	failed := lifecycle.IntentState{Revision: "rev1", Terminal: true, Failed: true}
	require.True(t, lifecycle.PerVersionIntent("rev1", item("cf", "h"), failed).Empty())
	// A later revision recovers independently of the prior failure.
	require.False(t, lifecycle.PerVersionIntent("rev2", item("cf", "h"), failed).Empty())
}

func TestPerVersionInProgressRevisionUpdates(t *testing.T) {
	p := lifecycle.PerVersionIntent("rev1", item("cf", "h"), lifecycle.IntentState{Revision: "rev1"})
	require.Equal(t, 1, p.Len())
	require.Equal(t, plan.OpUpdate, p.Actions[0].Op)
}

// ─── Run (mode realization) ──────────────────────────────────────────────────

func TestRunInvalidModeFailsClosed(t *testing.T) {
	exec := &fakeExecutor{}
	p := lifecycle.Converge([]lifecycle.Item{item("a", "h")}, nil)
	// Act
	_, err := lifecycle.Run(context.Background(), lifecycle.Mode("audit"), p, exec)
	// Assert: error, and nothing executed.
	require.Error(t, err)
	require.Empty(t, exec.executed)
}

func TestRunObserveExecutesNothing(t *testing.T) {
	exec := &fakeExecutor{}
	p := lifecycle.Converge([]lifecycle.Item{item("a", "h"), item("b", "h")}, nil)
	// Act
	res, err := lifecycle.Run(context.Background(), lifecycle.ModeObserve, p, exec)
	// Assert: the exact plan is returned, but zero actions run.
	require.NoError(t, err)
	require.Equal(t, lifecycle.ModeObserve, res.Mode)
	require.Equal(t, p, res.Plan)
	require.Empty(t, res.Executed)
	require.Empty(t, exec.executed)
}

func TestRunObserveAcceptsNilExecutor(t *testing.T) {
	// Arrange
	p := lifecycle.Converge([]lifecycle.Item{item("a", "h")}, nil)

	// Act
	res, err := lifecycle.Run(context.Background(), lifecycle.ModeObserve, p, nil)

	// Assert: observe is always zero-write and needs no executor configuration.
	require.NoError(t, err)
	require.Equal(t, p, res.Plan)
	require.Empty(t, res.Executed)
}

func TestRunActiveNilExecutorFailsClosed(t *testing.T) {
	// Arrange: a non-empty plan proves no action is silently skipped as success.
	p := lifecycle.Converge([]lifecycle.Item{item("a", "h")}, nil)

	// Act
	res, err := lifecycle.Run(context.Background(), lifecycle.ModeActive, p, nil)

	// Assert
	require.ErrorContains(t, err, "non-nil executor")
	require.Equal(t, p, res.Plan)
	require.Empty(t, res.Executed)
}

func TestRunActiveTypedNilExecutorFailsClosed(t *testing.T) {
	// Arrange: the interface itself is non-nil but contains a nil pointer.
	var exec *fakeExecutor
	p := lifecycle.Converge([]lifecycle.Item{item("a", "h")}, nil)

	// Act
	res, err := lifecycle.Run(context.Background(), lifecycle.ModeActive, p, exec)

	// Assert: Execute was never dereferenced or called.
	require.ErrorContains(t, err, "non-nil executor")
	require.Empty(t, res.Executed)
}

func TestRunActiveExecutesEveryAction(t *testing.T) {
	exec := &fakeExecutor{}
	p := lifecycle.Converge([]lifecycle.Item{item("a", "h"), item("b", "h")}, nil)
	// Act
	res, err := lifecycle.Run(context.Background(), lifecycle.ModeActive, p, exec)
	// Assert
	require.NoError(t, err)
	require.Len(t, res.Executed, 2)
	require.Len(t, exec.executed, 2)
}

func TestRunActiveAcceptsNonPointerExecutor(t *testing.T) {
	// Arrange + Act
	res, err := lifecycle.Run(context.Background(), lifecycle.ModeActive,
		lifecycle.Converge([]lifecycle.Item{item("a", "h")}, nil), valueExecutor{})

	// Assert
	require.NoError(t, err)
	require.Len(t, res.Executed, 1)
}

func TestRunIsolatesExecutorFacingMetadata(t *testing.T) {
	// Arrange: both actions intentionally share caller-owned metadata.
	original := reference(t, plan.ReferenceSecretPath, "/namespaces/app/secrets/database")
	replacement := reference(t, plan.ReferenceSecretPath, "/namespaces/app/secrets/other")
	shared := plan.Metadata{"credential": original}
	p := plan.Build([]plan.Action{
		{Op: plan.OpCreate, Target: plan.Target{Kind: plan.TargetSecret, ID: "a"}, Metadata: shared},
		{Op: plan.OpCreate, Target: plan.Target{Kind: plan.TargetSecret, ID: "b"}, Metadata: shared},
	})
	exec := &metadataMutatingExecutor{replacement: replacement}

	// Act
	res, err := lifecycle.Run(context.Background(), lifecycle.ModeActive, p, exec)

	// Assert: each executor call saw the pristine value, while executor mutation
	// affected neither the source plan nor either result projection.
	require.NoError(t, err)
	require.Equal(t, []plan.Reference{original, original}, exec.seen)
	for _, action := range p.Actions {
		require.Equal(t, original, action.Metadata["credential"])
		require.NotContains(t, action.Metadata, "injected")
	}
	for _, action := range append(res.Plan.Actions, res.Executed...) {
		require.Equal(t, original, action.Metadata["credential"])
		require.NotContains(t, action.Metadata, "injected")
	}
}

func TestRunActiveStopsAtFirstError(t *testing.T) {
	// Arrange: fail on the second action in deterministic order (target "b").
	exec := &fakeExecutor{failOn: "b"}
	p := lifecycle.Converge([]lifecycle.Item{item("a", "h"), item("b", "h"), item("c", "h")}, nil)
	// Act
	res, err := lifecycle.Run(context.Background(), lifecycle.ModeActive, p, exec)
	// Assert: it stops — only the pre-failure action executed, and no retry-storm.
	require.Error(t, err)
	require.Len(t, res.Executed, 1)
	require.Equal(t, "a", res.Executed[0].Target.ID)
}

// ─── Deletion-intent vocabulary ──────────────────────────────────────────────

func TestClassifyDeletionSpecRemovalDestroys(t *testing.T) {
	got := lifecycle.ClassifyDeletion(lifecycle.TriggerSpecRemoval, lifecycle.StatefulClass("cnpg"))
	require.Equal(t, lifecycle.IntentDestroy, got)
	require.True(t, got.Destructive())
}

func TestClassifyDeletionDecommissionDestroys(t *testing.T) {
	got := lifecycle.ClassifyDeletion(lifecycle.TriggerDecommission, lifecycle.StatefulClass("cnpg"))
	require.Equal(t, lifecycle.IntentDestroy, got)
}

func TestClassifyDeletionParentDeleteRetainsStateful(t *testing.T) {
	// Ordinary CR deletion orphans a stateful realization (never destroys it).
	got := lifecycle.ClassifyDeletion(lifecycle.TriggerParentDelete, lifecycle.StatefulClass("dragonfly-snapshot"))
	require.Equal(t, lifecycle.IntentRetain, got)
	require.False(t, got.Destructive())
}

func TestClassifyDeletionParentDeleteGarbageCollectsEphemeral(t *testing.T) {
	// The diskless Dragonfly cache is genuinely ephemeral: ordinary GC is fine.
	got := lifecycle.ClassifyDeletion(lifecycle.TriggerParentDelete, lifecycle.EphemeralClass("dragonfly-cache"))
	require.Equal(t, lifecycle.IntentGarbageCollect, got)
}

func TestClassifyDeletionParentDeleteFailsClosedToRetain(t *testing.T) {
	// A class that is neither stateful nor ephemeral, and a class marked both,
	// both fall through to the conservative retain default.
	require.Equal(t, lifecycle.IntentRetain,
		lifecycle.ClassifyDeletion(lifecycle.TriggerParentDelete, lifecycle.Class{Name: "unknown"}))
	require.Equal(t, lifecycle.IntentRetain,
		lifecycle.ClassifyDeletion(lifecycle.TriggerParentDelete, lifecycle.Class{Name: "both", Stateful: true, Ephemeral: true}))
}

func TestClassifyDeletionUnknownTriggerFailsClosedToRetain(t *testing.T) {
	// An unrecognised trigger can never destroy durable state.
	got := lifecycle.ClassifyDeletion(lifecycle.DeletionTrigger("mystery"), lifecycle.StatefulClass("cnpg"))
	require.Equal(t, lifecycle.IntentRetain, got)
}
