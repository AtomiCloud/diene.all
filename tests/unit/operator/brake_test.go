package operator_test

import (
	"testing"

	"github.com/AtomiCloud/diene.go-base/lib/operator/brake"
	"github.com/stretchr/testify/require"
)

func TestBrakeNoDeletesNeverTrips(t *testing.T) {
	require.False(t, brake.Evaluate(10, 0, 20).Tripped)
}

func TestBrakeEmptySetNeverTrips(t *testing.T) {
	require.False(t, brake.Evaluate(0, 5, 20).Tripped)
}

func TestBrakeUnderCapAllowed(t *testing.T) {
	// 1 of 10 = 10% <= 20% cap.
	require.False(t, brake.Evaluate(10, 1, 20).Tripped)
}

func TestBrakeOverCapTrips(t *testing.T) {
	// 5 of 10 = 50% > 20% cap.
	d := brake.Evaluate(10, 5, 20)
	require.True(t, d.Tripped)
	require.Equal(t, "BlastBrakeTripped", d.Reason)
	require.Contains(t, d.Message, "refusing to delete 5 of 10")
}

func TestBrakeZeroCapTripsOnAnyWrite(t *testing.T) {
	require.True(t, brake.Evaluate(10, 1, 0).Tripped)
}

func TestBrakeFullCapNeverTrips(t *testing.T) {
	require.False(t, brake.Evaluate(10, 10, 100).Tripped)
}
