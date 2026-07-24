package operator_test

import (
	"testing"

	"github.com/AtomiCloud/diene.go-base/lib/operator/note"
	"github.com/AtomiCloud/diene.go-base/lib/operator/plan"
	"github.com/stretchr/testify/require"
)

func sampleSpec() note.Spec {
	return note.Spec{Title: "Hello World", Body: "content", Category: "work", Replicas: 3}
}

func TestCopyName(t *testing.T) {
	require.Equal(t, "note-a-copy-2", note.CopyName("note-a", 2))
}

func TestPayload(t *testing.T) {
	require.Equal(t, "Hello World\ncontent", note.Payload(sampleSpec()))
}

func TestDesiredCopies(t *testing.T) {
	require.Equal(t, []string{"n-copy-0", "n-copy-1", "n-copy-2"}, note.DesiredCopies("n", sampleSpec()))
}

func TestDesiredCopiesZeroReplicas(t *testing.T) {
	require.Empty(t, note.DesiredCopies("n", note.Spec{Replicas: 0}))
}

func TestReadyConditionConverged(t *testing.T) {
	c := note.ReadyCondition(3, 3)
	require.Equal(t, plan.TypeReady, c.Type)
	require.Equal(t, plan.StatusTrue, c.Status)
	require.Equal(t, "Converged", c.Reason)
}

func TestReadyConditionConverging(t *testing.T) {
	c := note.ReadyCondition(3, 1)
	require.Equal(t, plan.TypeReady, c.Type)
	require.Equal(t, plan.StatusFalse, c.Status)
	require.Equal(t, "Converging", c.Reason)
	require.Contains(t, c.Message, "1 of 3")
}

func TestBrakeCondition(t *testing.T) {
	c := note.BrakeCondition("too many deletes")
	require.Equal(t, plan.TypeBlastBrakeTripped, c.Type)
	require.Equal(t, plan.StatusTrue, c.Status)
	require.Equal(t, "too many deletes", c.Message)
}
