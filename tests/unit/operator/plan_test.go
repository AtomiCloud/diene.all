package operator_test

import (
	"testing"

	"github.com/AtomiCloud/diene.go-base/lib/operator/plan"
	"github.com/stretchr/testify/require"
)

func TestDiffCreatesMissing(t *testing.T) {
	p := plan.Diff([]string{"a", "b"}, []string{"a"})
	require.Equal(t, []string{"b"}, p.Creates)
	require.Empty(t, p.Deletes)
	require.False(t, p.Empty())
}

func TestDiffDeletesUndesired(t *testing.T) {
	p := plan.Diff([]string{"a"}, []string{"a", "b"})
	require.Empty(t, p.Creates)
	require.Equal(t, []string{"b"}, p.Deletes)
	require.False(t, p.Empty())
}

func TestDiffCreatesAndDeletes(t *testing.T) {
	p := plan.Diff([]string{"a", "c"}, []string{"a", "b"})
	require.Equal(t, []string{"c"}, p.Creates)
	require.Equal(t, []string{"b"}, p.Deletes)
}

func TestDiffHealthyIsEmpty(t *testing.T) {
	p := plan.Diff([]string{"a", "b"}, []string{"a", "b"})
	require.True(t, p.Empty())
}

func TestConditionVocabulary(t *testing.T) {
	require.Equal(t, "Ready", plan.TypeReady)
	require.Equal(t, "Drifted", plan.TypeDrifted)
	require.Equal(t, "Conflict", plan.TypeConflict)
	require.Equal(t, "WaitingForEndpoint", plan.TypeWaitingForEndpoint)
	require.Equal(t, "BlastBrakeTripped", plan.TypeBlastBrakeTripped)
	require.Equal(t, "True", plan.StatusTrue)
	require.Equal(t, "False", plan.StatusFalse)
}
