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

func reference(t *testing.T, kind plan.ReferenceKind, locator string) plan.Reference {
	t.Helper()
	actual, err := plan.NewReference(kind, locator)
	require.NoError(t, err)
	return actual
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

func TestReferenceRequiresTypedAbsolutePointer(t *testing.T) {
	// Arrange + Act + Assert: a raw payload, invalid kind, and payload character
	// are rejected rather than silently becoming action metadata.
	_, err := plan.NewReference(plan.ReferenceSecretPath, "sk_live_plaintext")
	require.Error(t, err)
	_, err = plan.NewReference(plan.ReferenceKind("password"), "/valid/path")
	require.Error(t, err)
	_, err = plan.NewReference(plan.ReferenceSecretPath, "/secrets/database=value")
	require.Error(t, err)

	actual := reference(t, plan.ReferenceSecretPath, "/namespaces/app/secrets/database/keys/password")
	require.Equal(t, plan.ReferenceSecretPath, actual.Kind())
	require.Equal(t, "/namespaces/app/secrets/database/keys/password", actual.Locator())
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

func TestBuildOrdersEqualPrefixActionsDeterministically(t *testing.T) {
	// Arrange: every action shares the former kind/op/id/hash sort prefix and
	// differs only in destructive intent or metadata.
	refA := reference(t, plan.ReferenceVendorObject, "/accounts/main/resources/a")
	refB := reference(t, plan.ReferenceVendorObject, "/accounts/main/resources/b")
	base := plan.Action{
		Op:          plan.OpUpdate,
		Target:      plan.Target{Kind: plan.TargetVendor, ID: "same"},
		DetailsHash: "same-hash",
	}
	metadataA := base
	metadataA.Metadata = plan.Metadata{"resource": refA}
	metadataB := base
	metadataB.Metadata = plan.Metadata{"resource": refB}
	destructive := base
	destructive.Destructive = true
	destructive.Metadata = plan.Metadata{"resource": refA}

	// Act
	forward := plan.Build([]plan.Action{destructive, metadataB, metadataA})
	reverse := plan.Build([]plan.Action{metadataA, metadataB, destructive})

	// Assert: caller insertion order cannot break the canonical order.
	require.Equal(t, forward.Actions, reverse.Actions)
	require.Equal(t, refA, forward.Actions[0].Metadata["resource"])
	require.Equal(t, refB, forward.Actions[1].Metadata["resource"])
	require.True(t, forward.Actions[2].Destructive)
}

func TestBuildDeepCopiesCallerOwnedMetadata(t *testing.T) {
	// Arrange
	original := reference(t, plan.ReferenceSecretPath, "/namespaces/app/secrets/database")
	replacement := reference(t, plan.ReferenceSecretPath, "/namespaces/app/secrets/other")
	source := plan.Metadata{"credential": original}

	// Act: mutate the caller-owned source map only after Build returns.
	actual := plan.Build([]plan.Action{{
		Op:       plan.OpUpdate,
		Target:   plan.Target{Kind: plan.TargetSecret, ID: "database"},
		Metadata: source,
	}})
	source["credential"] = replacement
	source["new"] = replacement

	// Assert: the plan retains its independently owned, exact executor input.
	require.Equal(t, original, actual.Actions[0].Metadata["credential"])
	require.NotContains(t, actual.Actions[0].Metadata, "new")
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

func TestMetadataOnlyChangeAffectsEqualityAndDiffIdentity(t *testing.T) {
	// Arrange
	refA := reference(t, plan.ReferenceLedgerEntry, "/platforms/p/modules/a")
	refB := reference(t, plan.ReferenceLedgerEntry, "/platforms/p/modules/b")
	action := kube(plan.OpUpdate, "same", false)
	beforeAction := action
	beforeAction.Metadata = plan.Metadata{"ledger": refA}
	afterAction := action
	afterAction.Metadata = plan.Metadata{"ledger": refB}
	before := plan.Build([]plan.Action{beforeAction})
	after := plan.Build([]plan.Action{afterAction})

	// Act
	added, removed := after.Diff(before)

	// Assert
	require.False(t, after.Equal(before))
	require.Equal(t, []plan.Action{afterAction}, added)
	require.Equal(t, []plan.Action{beforeAction}, removed)
}

func TestMetadataIdentityCoversKeysKindsAndCardinality(t *testing.T) {
	// Arrange: keep the action prefix and locator fixed while varying each
	// remaining metadata identity dimension.
	secretRef := reference(t, plan.ReferenceSecretPath, "/objects/shared")
	ledgerRef := reference(t, plan.ReferenceLedgerEntry, "/objects/shared")
	base := kube(plan.OpUpdate, "same", false)
	withoutMetadata := plan.Build([]plan.Action{base})
	keyAAction := base
	keyAAction.Metadata = plan.Metadata{"a": secretRef}
	keyBAction := base
	keyBAction.Metadata = plan.Metadata{"b": secretRef}
	kindAction := base
	kindAction.Metadata = plan.Metadata{"a": ledgerRef}
	keyA := plan.Build([]plan.Action{keyAAction})
	keyB := plan.Build([]plan.Action{keyBAction})
	kind := plan.Build([]plan.Action{kindAction})

	// Act + Assert: key, kind, and metadata cardinality all affect identity in
	// both comparator directions; action multiplicity affects plan equality too.
	require.False(t, keyA.Equal(keyB))
	require.False(t, keyA.Equal(kind))
	require.False(t, withoutMetadata.Equal(keyA))
	require.False(t, keyA.Equal(withoutMetadata))
	require.False(t, keyA.Equal(plan.Build([]plan.Action{keyAAction, keyAAction})))
}

func TestDestructiveOnlyChangeAffectsDiffIdentity(t *testing.T) {
	// Arrange
	nondestructive := kube(plan.OpDelete, "same", false)
	destructive := kube(plan.OpDelete, "same", true)
	before := plan.Build([]plan.Action{nondestructive})
	after := plan.Build([]plan.Action{destructive})

	// Act
	added, removed := after.Diff(before)

	// Assert
	require.False(t, after.Equal(before))
	require.Equal(t, []plan.Action{destructive}, added)
	require.Equal(t, []plan.Action{nondestructive}, removed)
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

func TestDiffPreservesDuplicateActionMultiplicity(t *testing.T) {
	// Arrange: execution runs both identical actions, so diff identity must not
	// collapse them into a set.
	action := kube(plan.OpCreate, "duplicate", false)
	prior := plan.Build([]plan.Action{action})
	next := plan.Build([]plan.Action{action, action})

	// Act
	added, removed := next.Diff(prior)

	// Assert
	require.Equal(t, []plan.Action{action}, added)
	require.Empty(t, removed)
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
