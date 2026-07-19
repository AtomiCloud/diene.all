package operator_test

import (
	"bytes"
	"context"
	"testing"

	"github.com/minio/minio-go/v7"
	miniocreds "github.com/minio/minio-go/v7/pkg/credentials"
	"github.com/stretchr/testify/require"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/wait"

	"github.com/AtomiCloud/diene.go-base/adapters/operator/ledgerstore"
	"github.com/AtomiCloud/diene.go-base/lib/operator/ledger"
)

// startMinio brings up a throwaway MinIO and returns a client. It uses Docker via
// testcontainers, so this file's tests only run where Docker is available (CI int
// job and the local quiet window).
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

func coordinate(module string) ledger.Coordinate {
	return ledger.Coordinate{Platform: "diene", Landscape: "lapras", Class: "note", Module: module}
}

func TestMinioLedgerLifecycle(t *testing.T) {
	ctx := context.Background()
	client := startMinio(t)
	store := ledgerstore.NewMinioStore(client, "operator-template-ledger", "notes/")
	require.NoError(t, store.EnsureBucket(ctx))
	require.NoError(t, store.EnsureBucket(ctx)) // idempotent: bucket already exists

	svc := ledger.NewService(store)
	coord := coordinate("alpha")

	// Missing coordinate reports not-found, not an error.
	_, ok, err := store.Get(ctx, coord.Key())
	require.NoError(t, err)
	require.False(t, ok)

	// intent -> created -> confirmed.
	entry, err := svc.Reserve(ctx, coord, "ext-alpha", "secret/notes/alpha")
	require.NoError(t, err)
	require.Equal(t, ledger.PhaseIntent, entry.Phase)

	// Lookup-first: a second reserve adopts back the same entry.
	again, err := svc.Reserve(ctx, coord, "ext-other", "secret/other")
	require.NoError(t, err)
	require.Equal(t, "ext-alpha", again.ExternalID)

	advanced, ok, err := svc.Advance(ctx, coord)
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, ledger.PhaseCreated, advanced.Phase)

	advanced, _, err = svc.Advance(ctx, coord)
	require.NoError(t, err)
	require.Equal(t, ledger.PhaseConfirmed, advanced.Phase)

	// Orphan on delete; the external record is never destroyed.
	require.NoError(t, svc.Orphan(ctx, coord))
	got, ok, err := store.Get(ctx, coord.Key())
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, ledger.PhaseOrphaned, got.Phase)
}

func TestMinioLedgerCorruptObject(t *testing.T) {
	ctx := context.Background()
	client := startMinio(t)
	store := ledgerstore.NewMinioStore(client, "corrupt-bucket", "notes/")
	require.NoError(t, store.EnsureBucket(ctx))

	// Write a non-JSON object directly, then a Get must surface a decode error.
	garbage := []byte("not json")
	_, err := client.PutObject(ctx, "corrupt-bucket", "notes/diene/lapras/note/beta", bytes.NewReader(garbage), int64(len(garbage)), minio.PutObjectOptions{})
	require.NoError(t, err)

	_, _, err = store.Get(ctx, coordinate("beta").Key())
	require.Error(t, err)
}
