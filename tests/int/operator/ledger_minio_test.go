package operator_test

import (
	"bytes"
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/minio/minio-go/v7"
	miniocreds "github.com/minio/minio-go/v7/pkg/credentials"
	"github.com/stretchr/testify/require"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/wait"

	"github.com/AtomiCloud/diene.fleet-operator/adapters/operator/ledgerstore"
	"github.com/AtomiCloud/diene.fleet-operator/lib/operator/ledger"
)

// startMinio brings up a throwaway real MinIO. Only the focused integration
// tier invokes Docker; the test harness, not the adapter, provisions buckets.
func startMinio(t *testing.T) *minio.Client {
	t.Helper()
	ctx := context.Background()
	container, err := testcontainers.GenericContainer(ctx, testcontainers.GenericContainerRequest{
		ContainerRequest: testcontainers.ContainerRequest{
			Image:        "minio/minio:RELEASE.2024-01-16T16-07-38Z",
			Cmd:          []string{"server", "/data"},
			Env:          map[string]string{"MINIO_ROOT_USER": "minioadmin", "MINIO_ROOT_PASSWORD": "minioadmin"},
			ExposedPorts: []string{"9000/tcp"},
			WaitingFor:   wait.ForHTTP("/minio/health/live").WithPort("9000/tcp"),
		},
		Started: true,
	})
	require.NoError(t, err)
	t.Cleanup(func() { _ = container.Terminate(ctx) })

	endpoint, err := container.Endpoint(ctx, "")
	require.NoError(t, err)
	client, err := minio.New(endpoint, &minio.Options{
		Creds:  miniocreds.NewStaticV4("minioadmin", "minioadmin", ""),
		Secure: false,
	})
	require.NoError(t, err)
	return client
}

func bootstrapBucket(t *testing.T, client *minio.Client, bucket string) {
	t.Helper()
	require.NoError(t, client.MakeBucket(context.Background(), bucket, minio.MakeBucketOptions{}))
}

func minioCoordinate(module string) ledger.Coordinate {
	return ledger.Coordinate{
		Platform: "diene", Landscape: "lapras", Class: "postgres", Module: module,
		Vendor: "neon", Account: "production-a",
	}
}

func TestMinioLedgerLifecycle(t *testing.T) {
	ctx := context.Background()
	client := startMinio(t)
	bucket := "fleet-operator-ledger"
	bootstrapBucket(t, client, bucket)
	store := ledgerstore.NewMinioStore(client, bucket, "dependencies/")
	require.NoError(t, store.VerifyBucket(ctx))
	require.NoError(t, store.EnsureBucket(ctx))

	instant := time.Date(2026, time.July, 27, 8, 9, 10, 123456789, time.FixedZone("UTC+2", 2*60*60))
	service, err := ledger.NewStrictPurgeService(store, store, func() time.Time { return instant })
	require.NoError(t, err)
	coordinate := minioCoordinate("primary")

	_, found, err := store.Get(ctx, coordinate.Key())
	require.NoError(t, err)
	require.False(t, found)

	// #nosec G101 -- SecretPath is a non-secret pointer fixture, never a credential value.
	intent, err := service.IntentWithSpec(ctx, coordinate, ledger.IntentSpec{
		ExternalID: "neon-project-42", Region: "eu-central-1",
		SecretPath: "/diene/lapras/postgres/primary", Generation: 3,
		LastApplied: map[string]any{"compute": "medium", "storageGiB": 32},
	})
	require.NoError(t, err)
	require.Equal(t, ledger.PhaseIntent, intent.Phase)
	require.NotEmpty(t, intent.LastAppliedHash)
	require.Equal(t, "2026-07-27T06:09:10.123456789Z", intent.Timestamps.CreatedAt)

	created, err := service.Created(ctx, coordinate)
	require.NoError(t, err)
	require.Equal(t, ledger.PhaseCreated, created.Phase)
	confirmed, err := service.Confirm(ctx, coordinate)
	require.NoError(t, err)
	require.Equal(t, ledger.PhaseConfirmed, confirmed.Phase)

	require.NoError(t, service.Orphan(ctx, coordinate))
	orphaned, found, err := store.Get(ctx, coordinate.Key())
	require.NoError(t, err)
	require.True(t, found)
	require.Equal(t, ledger.PhaseOrphaned, orphaned.Phase)
	require.Equal(t, "neon-project-42", orphaned.ExternalID)

	adopted, err := service.Adopt(ctx, coordinate)
	require.NoError(t, err)
	require.Equal(t, ledger.PhaseCreated, adopted.Phase)
	confirmed, err = service.Confirm(ctx, coordinate)
	require.NoError(t, err)
	require.Equal(t, ledger.PhaseConfirmed, confirmed.Phase)

	replayed, err := service.IntentWithSpec(ctx, coordinate, ledger.IntentSpec{
		ExternalID: "must-not-replace", SecretPath: "/other", LastApplied: make(chan int),
	})
	require.NoError(t, err)
	require.Equal(t, "neon-project-42", replayed.ExternalID)

	proof, err := ledger.NewTombstoneProof(true, true, true)
	require.NoError(t, err)
	tombstoned, err := service.Tombstone(ctx, coordinate, proof)
	require.NoError(t, err)
	require.Equal(t, ledger.PhaseTombstoned, tombstoned.Phase)
	require.Equal(t, "2026-08-03T06:09:10.123456789Z", tombstoned.Timestamps.RetainUntil)

	stat, err := client.StatObject(ctx, bucket, "dependencies/"+coordinate.Key(), minio.StatObjectOptions{})
	require.NoError(t, err)
	require.Equal(t, "application/json", stat.ContentType)

	permit, err := ledger.NewPurgePermit(true, true, true, true)
	require.NoError(t, err)
	require.NoError(t, service.Purge(ctx, coordinate, permit))
	_, found, err = store.Get(ctx, coordinate.Key())
	require.NoError(t, err)
	require.False(t, found)
	require.NoError(t, service.Purge(ctx, coordinate, permit)) // absent-object purge is idempotent
}

func TestMinioLedgerSchemaRoundTripsAndReadsOldEntries(t *testing.T) {
	ctx := context.Background()
	client := startMinio(t)
	bucket := "schema-ledger"
	bootstrapBucket(t, client, bucket)
	store := ledgerstore.NewMinioStore(client, bucket, "dependencies/")

	coordinate := minioCoordinate("full-schema")
	expected := ledger.Entry{
		Coordinate: coordinate, Phase: ledger.PhaseConfirmed, ExternalID: "external-full",
		Vendor: coordinate.Vendor, Account: coordinate.Account, Region: "eu-west-1",
		SecretPath: "/secret/reference", Generation: 9, LastAppliedHash: "sha256-value",
		Timestamps: ledger.Timestamps{
			CreatedAt: "2026-07-27T06:09:10.123456789Z", UpdatedAt: "2026-07-27T07:08:09.987654321Z",
			OrphanedAt: "2026-07-27T06:30:00.000000001Z",
		},
	}
	require.NoError(t, store.Put(ctx, expected))
	actual, found, err := store.Get(ctx, coordinate.Key())
	require.NoError(t, err)
	require.True(t, found)
	require.Equal(t, expected, actual)
	parsed, err := ledger.ParseTimestamp(actual.Timestamps.UpdatedAt)
	require.NoError(t, err)
	require.Equal(t, 987654321, parsed.Nanosecond())

	legacyCoordinate := minioCoordinate("legacy")
	legacyJSON := []byte(`{"coordinate":{"platform":"diene","landscape":"lapras","class":"postgres","module":"legacy"},"phase":"confirmed","externalId":"old-external","secretPath":"/old/ref"}`)
	_, err = client.PutObject(
		ctx, bucket, "dependencies/"+legacyCoordinate.Key(), bytes.NewReader(legacyJSON), int64(len(legacyJSON)),
		minio.PutObjectOptions{ContentType: "application/json"},
	)
	require.NoError(t, err)
	legacy, found, err := store.Get(ctx, legacyCoordinate.Key())
	require.NoError(t, err)
	require.True(t, found)
	require.Equal(t, "old-external", legacy.ExternalID)
	require.Equal(t, "/old/ref", legacy.SecretPath)
	require.Empty(t, legacy.Vendor)
	require.Empty(t, legacy.Account)
	require.Zero(t, legacy.Generation)
	require.Equal(t, ledger.Timestamps{}, legacy.Timestamps)
}

func TestMinioLedgerCorruptObject(t *testing.T) {
	ctx := context.Background()
	client := startMinio(t)
	bucket := "corrupt-ledger"
	bootstrapBucket(t, client, bucket)
	store := ledgerstore.NewMinioStore(client, bucket, "dependencies/")
	coordinate := minioCoordinate("corrupt")

	garbage := []byte("not json")
	_, err := client.PutObject(
		ctx, bucket, "dependencies/"+coordinate.Key(), bytes.NewReader(garbage), int64(len(garbage)),
		minio.PutObjectOptions{},
	)
	require.NoError(t, err)
	_, _, err = store.Get(ctx, coordinate.Key())
	require.Error(t, err)

	// Prove the complete schema is ordinary JSON and remains inspectable by
	// independent S3 tooling rather than relying on a private encoding.
	encoded, err := json.Marshal(ledger.Entry{Coordinate: coordinate, Phase: ledger.PhaseIntent})
	require.NoError(t, err)
	require.Contains(t, string(encoded), `"coordinate"`)
}
