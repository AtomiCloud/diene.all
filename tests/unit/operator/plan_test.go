package operator_test

import (
	"testing"

	"github.com/AtomiCloud/diene.fleet-operator/lib/operator/plan"
	"github.com/stretchr/testify/require"
)

func TestPlanEmpty(t *testing.T) {
	require.True(t, plan.Plan{}.Empty())
	require.False(t, plan.Plan{Creates: []string{"a"}}.Empty())
	require.False(t, plan.Plan{Deletes: []string{"b"}}.Empty())
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
