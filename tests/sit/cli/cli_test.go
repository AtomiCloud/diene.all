package cli_test

// DOMAIN WIRING: replaceable Note/KV compiled-artifact Redis journey.
import (
	"context"
	"os/exec"
	"testing"

	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/wait"
)

func TestCompiledArtifactRedisJourney(t *testing.T) {
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
	// #nosec G204 -- the executable is fixed; only the isolated testcontainer endpoint is dynamic.
	output, err := exec.CommandContext(ctx, "../../../dist/go-base", "note", endpoint, "Sample Journey", "connected").CombinedOutput()
	if err != nil {
		t.Fatalf("run compiled artifact: %v\n%s", err, output)
	}
	if got, want := string(output), "sample-journey=connected\n"; got != want {
		t.Fatalf("compiled artifact output = %q, want %q", got, want)
	}
}

// END DOMAIN WIRING
