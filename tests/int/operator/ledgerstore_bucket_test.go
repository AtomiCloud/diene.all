package operator_test

import (
	"context"
	"errors"
	"testing"

	"github.com/minio/minio-go/v7"
	"github.com/stretchr/testify/require"

	"github.com/AtomiCloud/diene.fleet-operator/adapters/operator/ledgerstore"
	"github.com/AtomiCloud/diene.fleet-operator/lib/operator/ledger"
)

func TestLedgerStoreBucketVerificationNeverCreates(t *testing.T) {
	ctx := context.Background()
	client := startMinio(t)
	store := ledgerstore.NewMinioStore(client, "bootstrap-owned-ledger", "dependencies/")

	before, err := client.ListBuckets(ctx)
	require.NoError(t, err)
	require.Empty(t, before)

	err = store.VerifyBucket(ctx)
	require.ErrorIs(t, err, ledgerstore.ErrBucketMissing)
	require.Contains(t, err.Error(), "bootstrap-owned-ledger")
	require.Contains(t, err.Error(), "L0 bootstrap")
	err = store.EnsureBucket(ctx)
	require.ErrorIs(t, err, ledgerstore.ErrBucketMissing)

	afterFailure, err := client.ListBuckets(ctx)
	require.NoError(t, err)
	require.Equal(t, before, afterFailure, "verification must not create a bucket")

	bootstrapBucket(t, client, "bootstrap-owned-ledger")
	require.NoError(t, store.VerifyBucket(ctx))
	entry := ledger.Entry{
		Coordinate: minioCoordinate("bucket-contract"), Phase: ledger.PhaseIntent,
		ExternalID: "external", Vendor: "neon", Account: "production-a", SecretPath: "/secret/ref",
	}
	require.NoError(t, store.Put(ctx, entry))
	_, found, err := store.Get(ctx, entry.Coordinate.Key())
	require.NoError(t, err)
	require.True(t, found)

	afterOperations, err := client.ListBuckets(ctx)
	require.NoError(t, err)
	require.Len(t, afterOperations, 1)
	require.Equal(t, "bootstrap-owned-ledger", afterOperations[0].Name)
}

func TestLedgerStoreFailsLoudlyAgainstAbsentBucket(t *testing.T) {
	ctx := context.Background()
	store := ledgerstore.NewMinioStore(startMinio(t), "absent-ledger", "dependencies/")
	entry := ledger.Entry{
		Coordinate: minioCoordinate("absent"), Phase: ledger.PhaseIntent,
		ExternalID: "external", Vendor: "neon", Account: "production-a", SecretPath: "/secret/ref",
	}

	require.Error(t, store.Put(ctx, entry))
	_, found, err := store.Get(ctx, entry.Coordinate.Key())
	require.Error(t, err)
	require.False(t, found)

	// RemoveObject is an adapter capability rather than part of ledger.Store.
	// MinIO may report an absent bucket as either a direct error or an idempotent
	// missing delete; either outcome must not create storage.
	purgeErr := store.Purge(ctx, entry.Coordinate.Key())
	if purgeErr != nil {
		var response minio.ErrorResponse
		require.True(t, errors.As(purgeErr, &response) || minio.ToErrorResponse(purgeErr).Code != "")
	}
}
