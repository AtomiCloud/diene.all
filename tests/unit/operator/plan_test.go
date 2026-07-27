package operator_test

import (
	"testing"

	"github.com/AtomiCloud/diene.fleet-operator/lib/operator/conditions"
	"github.com/AtomiCloud/diene.fleet-operator/lib/operator/plan"
	"github.com/stretchr/testify/require"
)

// kube builds a Kubernetes-target action for tests.
func kube(op plan.Operation, id string, destructive bool) plan.Action {
	return plan.Action{
		Op:          op,
		Target:      plan.Target{Kind: plan.TargetKubernetes, ID: id},
		Destructive: destructive,
		DetailsHash: plan.HashDetails(id, string(op)),
	}
}

func TestPlanEmpty(t *testing.T) {
	// Arrange + Act + Assert: a zero plan and an empty-built plan are both empty.
	require.True(t, plan.Plan{}.Empty())
	require.True(t, plan.Build(nil).Empty())
	require.False(t, plan.Build([]plan.Action{kube(plan.OpCreate, "a", false)}).Empty())
}

func TestHashDetailsDeterministicAndDistinct(t *testing.T) {
	// Arrange
	a := plan.HashDetails("neon", "project-1", "region-x")
	// Act + Assert: stable across calls, distinct across inputs, boundary-safe.
	require.Equal(t, a, plan.HashDetails("neon", "project-1", "region-x"))
	require.NotEqual(t, a, plan.HashDetails("neon", "project-2", "region-x"))
	require.NotEqual(t, plan.HashDetails("ab", "c"), plan.HashDetails("a", "bc"))
	require.Len(t, a, 16)
}

func TestBuildIsDeterministicRegardlessOfInputOrder(t *testing.T) {
	// Arrange: two input orders over the same actions.
	forward := []plan.Action{
		kube(plan.OpCreate, "a", false),
		kube(plan.OpDelete, "b", true),
		{Op: plan.OpUpdate, Target: plan.Target{Kind: plan.TargetVendor, ID: "z"}},
	}
	reverse := []plan.Action{forward[2], forward[1], forward[0]}
	// Act
	p1 := plan.Build(forward)
	p2 := plan.Build(reverse)
	// Assert: identical ordering, so equal.
	require.Equal(t, p1.Actions, p2.Actions)
	require.True(t, p1.Equal(p2))
}

func TestCountsAndDestructiveSubset(t *testing.T) {
	// Arrange
	p := plan.Build([]plan.Action{
		kube(plan.OpCreate, "a", false),
		kube(plan.OpCreate, "b", false),
		kube(plan.OpUpdate, "c", false),
		kube(plan.OpDelete, "d", true),
		kube(plan.OpAdopt, "e", false),
	})
	// Act + Assert
	require.Equal(t, 5, p.Len())
	require.Equal(t, 2, p.Count(plan.OpCreate))
	require.Equal(t, 1, p.Count(plan.OpUpdate))
	require.Equal(t, 1, p.Count(plan.OpDelete))
	require.Equal(t, 1, p.Count(plan.OpAdopt))
	require.Len(t, p.Destructive(), 1)
	require.Equal(t, 1, p.DestructiveCount())
	require.Equal(t, "d", p.Destructive()[0].Target.ID)
}

func TestEqualDetectsDifference(t *testing.T) {
	// Arrange: same members except one destructive flag flip.
	base := plan.Build([]plan.Action{kube(plan.OpDelete, "a", true), kube(plan.OpCreate, "b", false)})
	same := plan.Build([]plan.Action{kube(plan.OpCreate, "b", false), kube(plan.OpDelete, "a", true)})
	diff := plan.Build([]plan.Action{kube(plan.OpDelete, "a", false), kube(plan.OpCreate, "b", false)})
	// Act + Assert
	require.True(t, base.Equal(same))
	require.False(t, base.Equal(diff))
}

func TestDiffReportsAddedAndRemoved(t *testing.T) {
	// Arrange
	prior := plan.Build([]plan.Action{kube(plan.OpCreate, "keep", false), kube(plan.OpDelete, "gone", true)})
	next := plan.Build([]plan.Action{kube(plan.OpCreate, "keep", false), kube(plan.OpCreate, "fresh", false)})
	// Act
	added, removed := next.Diff(prior)
	// Assert
	require.Len(t, added, 1)
	require.Equal(t, "fresh", added[0].Target.ID)
	require.Len(t, removed, 1)
	require.Equal(t, "gone", removed[0].Target.ID)
}

func TestHumanSummary(t *testing.T) {
	// Arrange + Act + Assert: empty vs populated.
	require.Equal(t, "no changes", plan.Build(nil).HumanSummary())
	p := plan.Build([]plan.Action{
		kube(plan.OpCreate, "a", false),
		kube(plan.OpUpdate, "b", false),
		kube(plan.OpDelete, "c", true),
		kube(plan.OpAdopt, "d", false),
	})
	summary := p.HumanSummary()
	require.Contains(t, summary, "4 actions")
	require.Contains(t, summary, "1 create")
	require.Contains(t, summary, "1 destructive")
}

func TestConditionSummary(t *testing.T) {
	// Arrange + Act: empty plan is in sync.
	inSync := plan.Build(nil).ConditionSummary()
	// Assert
	require.Equal(t, conditions.TypeDrifted, inSync.Type)
	require.Equal(t, conditions.StatusFalse, inSync.Status)
	require.Equal(t, "InSync", inSync.Reason)

	// Arrange + Act: populated plan reports would-apply.
	drift := plan.Build([]plan.Action{kube(plan.OpDelete, "a", true)}).ConditionSummary()
	// Assert
	require.Equal(t, conditions.StatusTrue, drift.Status)
	require.Equal(t, "WouldApply", drift.Reason)
	require.Contains(t, drift.Message, "1 destructive")
}

func TestConditionVocabularyCompatFacade(t *testing.T) {
	// Assert: the legacy plan.* symbols still resolve to the shared vocabulary.
	require.Equal(t, conditions.TypeReady, plan.TypeReady)
	require.Equal(t, conditions.TypeDrifted, plan.TypeDrifted)
	require.Equal(t, conditions.TypeConflict, plan.TypeConflict)
	require.Equal(t, conditions.TypeWaitingForEndpoint, plan.TypeWaitingForEndpoint)
	require.Equal(t, conditions.TypeBlastBrakeTripped, plan.TypeBlastBrakeTripped)
	require.Equal(t, conditions.StatusTrue, plan.StatusTrue)
	require.Equal(t, conditions.StatusFalse, plan.StatusFalse)
	// The alias is a usable struct type interchangeable with conditions.Condition.
	c := plan.Condition{Type: plan.TypeReady, Status: conditions.StatusTrue, Reason: "Converged"}
	require.Equal(t, plan.TypeReady, c.Type)
	require.Equal(t, "True", c.Status)
	require.Equal(t, "Converged", c.Reason)
}
