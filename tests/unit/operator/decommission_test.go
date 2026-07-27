package operator_test

import (
	"errors"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/AtomiCloud/diene.fleet-operator/lib/operator/conditions"
	"github.com/AtomiCloud/diene.fleet-operator/lib/operator/decommission"
	"github.com/AtomiCloud/diene.fleet-operator/lib/operator/ledger"
)

func clearReferences() bool { return false }

func authorizedTarget() bool { return true }

func TestDecommissionHappyLadderProducesLedgerPermit(t *testing.T) {
	flow := decommission.New(clearReferences, authorizedTarget)

	refs, err := flow.RefsClear()
	require.NoError(t, err)
	snapshot, err := flow.Snapshotted(refs, decommission.Completed())
	require.NoError(t, err)
	externals, err := flow.ExternalsDeleted(snapshot, decommission.Completed())
	require.NoError(t, err)
	authorization, err := flow.PreparePurge(externals)
	require.NoError(t, err)
	require.NotEqual(t, ledger.PurgePermit{}, authorization.Permit)
	ledgerPurged, err := flow.LedgerPurged(authorization, decommission.Completed())
	require.NoError(t, err)
	targetDeleted, err := flow.TargetDeleted(ledgerPurged, decommission.Completed())
	require.NoError(t, err)
	selfDelete, err := flow.SelfDelete(targetDeleted)
	require.NoError(t, err)
	require.NotEqual(t, decommission.SelfDeleteAuthorization{}, selfDelete)

	conditionsByStep := []conditions.Condition{
		refs.Condition(), snapshot.Condition(), externals.Condition(), ledgerPurged.Condition(), targetDeleted.Condition(),
	}
	require.Equal(t, []string{
		conditions.TypeRefsClear, conditions.TypeSnapshotted, conditions.TypeExternalsDeleted,
		conditions.TypeLedgerPurged, conditions.TypeTargetDeleted,
	}, []string{
		conditionsByStep[0].Type, conditionsByStep[1].Type, conditionsByStep[2].Type,
		conditionsByStep[3].Type, conditionsByStep[4].Type,
	})
	for _, condition := range conditionsByStep {
		require.Equal(t, conditions.StatusTrue, condition.Status)
	}
}

func TestDecommissionReferencesFailClosed(t *testing.T) {
	for _, testCase := range []struct {
		name    string
		blocker decommission.ReferencesBlocked
	}{
		{name: "missing predicate", blocker: nil},
		{name: "references remain", blocker: func() bool { return true }},
	} {
		t.Run(testCase.name, func(t *testing.T) {
			flow := decommission.New(testCase.blocker, authorizedTarget)
			_, err := flow.RefsClear()
			require.ErrorIs(t, err, decommission.ErrReferencesBlocked)
		})
	}
}

func TestDecommissionFalseProofsCannotProducePermit(t *testing.T) {
	t.Run("snapshot", func(t *testing.T) {
		flow := decommission.New(clearReferences, authorizedTarget)
		refs, err := flow.RefsClear()
		require.NoError(t, err)
		_, err = flow.Snapshotted(refs, decommission.Completion{})
		require.ErrorIs(t, err, decommission.ErrProofFailed)
	})

	t.Run("external delete", func(t *testing.T) {
		flow, _, snapshot := flowAtSnapshot(t)
		_, err := flow.ExternalsDeleted(snapshot, decommission.Completion{})
		require.ErrorIs(t, err, decommission.ErrProofFailed)
	})

	t.Run("target authorization", func(t *testing.T) {
		for _, target := range []decommission.TargetAuthorized{nil, func() bool { return false }} {
			flow, externals := flowAtExternalsDeleted(t, target)
			_, err := flow.PreparePurge(externals)
			require.ErrorIs(t, err, ledger.ErrInvalidPurgePermit)
		}
	})

	t.Run("ledger purge", func(t *testing.T) {
		flow, authorization := flowAtPurgeAuthorization(t)
		_, err := flow.LedgerPurged(authorization, decommission.Completion{})
		require.ErrorIs(t, err, decommission.ErrProofFailed)
	})

	t.Run("target delete", func(t *testing.T) {
		flow, ledgerPurged := flowAtLedgerPurged(t)
		_, err := flow.TargetDeleted(ledgerPurged, decommission.Completion{})
		require.ErrorIs(t, err, decommission.ErrProofFailed)
	})
}

func TestDecommissionRejectsSkippedOutOfOrderAndReplayedProofs(t *testing.T) {
	flow := decommission.New(clearReferences, authorizedTarget)
	_, err := flow.Snapshotted(decommission.RefsClearProof{}, decommission.Completed())
	require.ErrorIs(t, err, decommission.ErrInvalidProof)

	refs, err := flow.RefsClear()
	require.NoError(t, err)
	_, err = flow.RefsClear()
	require.ErrorIs(t, err, decommission.ErrOutOfOrder)
	_, err = flow.ExternalsDeleted(decommission.SnapshotProof{}, decommission.Completed())
	require.ErrorIs(t, err, decommission.ErrInvalidProof)

	snapshot, err := flow.Snapshotted(refs, decommission.Completed())
	require.NoError(t, err)
	_, err = flow.Snapshotted(refs, decommission.Completed())
	require.ErrorIs(t, err, decommission.ErrOutOfOrder)
	externals, err := flow.ExternalsDeleted(snapshot, decommission.Completed())
	require.NoError(t, err)
	authorization, err := flow.PreparePurge(externals)
	require.NoError(t, err)
	_, err = flow.PreparePurge(externals)
	require.ErrorIs(t, err, decommission.ErrOutOfOrder)

	foreignFlow, foreignAuthorization := flowAtPurgeAuthorization(t)
	_, err = flow.LedgerPurged(foreignAuthorization, decommission.Completed())
	require.ErrorIs(t, err, decommission.ErrInvalidProof)
	ledgerPurged, err := flow.LedgerPurged(authorization, decommission.Completed())
	require.NoError(t, err)
	_, err = flow.LedgerPurged(authorization, decommission.Completed())
	require.ErrorIs(t, err, decommission.ErrOutOfOrder)
	targetDeleted, err := flow.TargetDeleted(ledgerPurged, decommission.Completed())
	require.NoError(t, err)
	_, err = flow.TargetDeleted(ledgerPurged, decommission.Completed())
	require.ErrorIs(t, err, decommission.ErrOutOfOrder)
	_, err = flow.SelfDelete(targetDeleted)
	require.NoError(t, err)
	_, err = flow.SelfDelete(targetDeleted)
	require.ErrorIs(t, err, decommission.ErrOutOfOrder)
	require.NotNil(t, foreignFlow)
}

func TestDecommissionNilFlowFailsWithoutProof(t *testing.T) {
	var flow *decommission.Flow
	_, err := flow.RefsClear()
	require.ErrorIs(t, err, decommission.ErrOutOfOrder)

	_, err = flow.Snapshotted(decommission.RefsClearProof{}, decommission.Completed())
	require.ErrorIs(t, err, decommission.ErrInvalidProof)
	require.False(t, errors.Is(err, decommission.ErrProofFailed))
}

func flowAtSnapshot(t *testing.T) (*decommission.Flow, decommission.RefsClearProof, decommission.SnapshotProof) {
	t.Helper()
	flow := decommission.New(clearReferences, authorizedTarget)
	refs, err := flow.RefsClear()
	require.NoError(t, err)
	snapshot, err := flow.Snapshotted(refs, decommission.Completed())
	require.NoError(t, err)
	return flow, refs, snapshot
}

func flowAtExternalsDeleted(t *testing.T, target decommission.TargetAuthorized) (*decommission.Flow, decommission.ExternalsDeletedProof) {
	t.Helper()
	flow := decommission.New(clearReferences, target)
	refs, err := flow.RefsClear()
	require.NoError(t, err)
	snapshot, err := flow.Snapshotted(refs, decommission.Completed())
	require.NoError(t, err)
	externals, err := flow.ExternalsDeleted(snapshot, decommission.Completed())
	require.NoError(t, err)
	return flow, externals
}

func flowAtPurgeAuthorization(t *testing.T) (*decommission.Flow, decommission.PurgeAuthorization) {
	t.Helper()
	flow, externals := flowAtExternalsDeleted(t, authorizedTarget)
	authorization, err := flow.PreparePurge(externals)
	require.NoError(t, err)
	return flow, authorization
}

func flowAtLedgerPurged(t *testing.T) (*decommission.Flow, decommission.LedgerPurgedProof) {
	t.Helper()
	flow, authorization := flowAtPurgeAuthorization(t)
	ledgerPurged, err := flow.LedgerPurged(authorization, decommission.Completed())
	require.NoError(t, err)
	return flow, ledgerPurged
}
