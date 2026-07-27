package operator_test

import (
	"testing"

	"github.com/AtomiCloud/diene.fleet-operator/lib/operator/conditions"
	"github.com/stretchr/testify/require"
)

func TestConditionConstructors(t *testing.T) {
	// Arrange + Act + Assert: each constructor stamps the right status.
	require.Equal(t, conditions.StatusTrue, conditions.True(conditions.TypeReady, "R", "m").Status)
	require.Equal(t, conditions.StatusFalse, conditions.False(conditions.TypeReady, "R", "m").Status)
	require.Equal(t, conditions.StatusUnknown, conditions.Unknown(conditions.TypeReady, "R", "m").Status)

	c := conditions.New(conditions.TypeProvisioned, conditions.StatusTrue, "Done", "provisioned")
	require.Equal(t, conditions.TypeProvisioned, c.Type)
	require.Equal(t, "Done", c.Reason)
	require.Equal(t, "provisioned", c.Message)
	require.Empty(t, c.Module)
}

func TestWithModule(t *testing.T) {
	base := conditions.True(conditions.TypeSecretWritten, "Written", "ok")
	scoped := base.WithModule("postgres")
	require.Equal(t, "postgres", scoped.Module)
	require.Empty(t, base.Module) // original unchanged (value receiver)
}

func TestUpsertAppendsNewType(t *testing.T) {
	// Arrange
	list := []conditions.Condition{conditions.True(conditions.TypeReady, "R", "ok")}
	// Act
	out := conditions.Upsert(list, conditions.True(conditions.TypeProvisioned, "P", "ok"))
	// Assert
	require.Len(t, out, 2)
	require.Len(t, list, 1) // input not grown
}

func TestUpsertReplacesSameTypeSameModule(t *testing.T) {
	// Arrange
	list := []conditions.Condition{conditions.False(conditions.TypeReady, "Converging", "1 of 2")}
	// Act
	out := conditions.Upsert(list, conditions.True(conditions.TypeReady, "Converged", "done"))
	// Assert: replaced in place, not appended.
	require.Len(t, out, 1)
	require.Equal(t, conditions.StatusTrue, out[0].Status)
	require.Equal(t, conditions.StatusFalse, list[0].Status) // input untouched
}

func TestUpsertSameTypeDifferentModuleAppends(t *testing.T) {
	// Arrange: same type but different module is a distinct condition.
	list := []conditions.Condition{conditions.True(conditions.TypeReady, "R", "ok").WithModule("a")}
	// Act
	out := conditions.Upsert(list, conditions.True(conditions.TypeReady, "R", "ok").WithModule("b"))
	// Assert
	require.Len(t, out, 2)
}

func TestModuleSetIsolation(t *testing.T) {
	// Arrange
	s := conditions.NewModuleSet()
	// Act: two modules, and a replace within one.
	s.Set("postgres", conditions.False(conditions.TypeProvisioned, "Provisioning", "…"))
	s.Set("redis", conditions.True(conditions.TypeProvisioned, "Done", "ok"))
	s.Set("postgres", conditions.True(conditions.TypeProvisioned, "Done", "ok")) // replace
	// Assert: replace stayed within postgres; redis untouched; order preserved.
	require.Equal(t, []string{"postgres", "redis"}, s.Modules())
	require.Len(t, s.For("postgres"), 1)
	require.Equal(t, conditions.StatusTrue, s.For("postgres")[0].Status)
	require.Equal(t, "postgres", s.For("postgres")[0].Module)
	require.Len(t, s.For("redis"), 1)
	require.Equal(t, conditions.StatusTrue, s.For("redis")[0].Status)
	require.Nil(t, s.For("absent"))
}

func TestVocabularyCoversAuditedConditions(t *testing.T) {
	// Assert: a representative slice across every controller family is present and
	// distinctly spelled (spot-check the audited set).
	all := []string{
		conditions.TypeReady, conditions.TypeDrifted, conditions.TypeConflict,
		conditions.TypeWaitingForEndpoint, conditions.TypeBlastBrakeTripped,
		conditions.TypeProvisioned, conditions.TypeSecretWritten, conditions.TypeUnresolved,
		conditions.TypeNotInEnvelope, conditions.TypeSecretRetained, conditions.TypeDeclarerChanged,
		conditions.TypeForkUnsupported, conditions.TypeQuotaExhausted,
		conditions.TypeInfisicalProvisioned, conditions.TypeSoSRegistered, conditions.TypePipelineRendered,
		conditions.TypeOrphanedSource, conditions.TypeConfigCompiled, conditions.TypeSecretsFanned,
		conditions.TypeHomeChangeBlocked, conditions.TypeTargetNotServed, conditions.TypeAccepted,
		conditions.TypeUnknownProvider, conditions.TypeOrphanedProvider, conditions.TypeTenantProvisioned,
		conditions.TypeRefsClear, conditions.TypeSnapshotted, conditions.TypeExternalsDeleted,
		conditions.TypeLedgerPurged, conditions.TypeTargetDeleted, conditions.TypeRecordPublished,
		conditions.TypeNoActiveServers, conditions.TypeVersionFound, conditions.TypeRolloutProgressing,
		conditions.TypeRolloutComplete, conditions.TypeDriftDetected, conditions.TypeFailed,
		conditions.TypePublished, conditions.TypeSchemaInvalid, conditions.TypeStale,
	}
	seen := map[string]bool{}
	for _, typ := range all {
		require.NotEmpty(t, typ)
		require.False(t, seen[typ], "duplicate condition spelling %q", typ)
		seen[typ] = true
	}
}
