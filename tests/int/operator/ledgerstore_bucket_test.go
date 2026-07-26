package operator_test

import (
	"errors"
	"testing"

	"github.com/minio/minio-go/v7"
	"github.com/stretchr/testify/require"

	"github.com/AtomiCloud/diene.fleet-operator/adapters/operator/ledgerstore"
)

// TestIsBucketExistsRace pins the MakeBucket race tolerance: the two already-exists
// codes a losing concurrent creator sees are success, everything else propagates.
// A real MinIO cannot deterministically schedule the concurrent-startup race, so
// the classification is exercised directly with the S3 error responses minio-go
// surfaces.
func TestIsBucketExistsRace(t *testing.T) {
	require.True(t, ledgerstore.IsBucketExistsRace(minio.ErrorResponse{Code: "BucketAlreadyOwnedByYou"}))
	require.True(t, ledgerstore.IsBucketExistsRace(minio.ErrorResponse{Code: "BucketAlreadyExists"}))
	require.False(t, ledgerstore.IsBucketExistsRace(minio.ErrorResponse{Code: "AccessDenied"}))
	require.False(t, ledgerstore.IsBucketExistsRace(errors.New("dial tcp: connection refused")))
}
