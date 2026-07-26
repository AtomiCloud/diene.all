package kv_test

import (
	"context"
	"testing"

	"github.com/AtomiCloud/diene.go-consumer/adapters/kv"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/wait"
)

func TestRedisStore(t *testing.T) {
	ctx := context.Background()
	container, err := testcontainers.GenericContainer(ctx, testcontainers.GenericContainerRequest{
		ContainerRequest: testcontainers.ContainerRequest{
			Image:        "redis:7.4.5-alpine",
			ExposedPorts: []string{"6379/tcp"},
			WaitingFor:   wait.ForLog("Ready to accept connections"),
		},
		Started: true,
	})
	if err != nil {
		t.Fatalf("start Redis container: %v", err)
	}
	t.Cleanup(func() {
		if terminateErr := container.Terminate(ctx); terminateErr != nil {
			t.Errorf("terminate Redis container: %v", terminateErr)
		}
	})

	endpoint, err := container.Endpoint(ctx, "")
	if err != nil {
		t.Fatalf("resolve Redis endpoint: %v", err)
	}
	store := kv.NewRedisStore(endpoint)
	if saveErr := store.Save(ctx, "notes:integration", "connected"); saveErr != nil {
		t.Fatalf("Save() error = %v", saveErr)
	}
	got, err := store.Load(ctx, "notes:integration")
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if got != "connected" {
		t.Fatalf("Load() = %q, want %q", got, "connected")
	}
	if err := store.Close(); err != nil {
		t.Fatalf("Close() error = %v", err)
	}
}
