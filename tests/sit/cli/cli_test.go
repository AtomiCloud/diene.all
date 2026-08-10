package cli_test

// DOMAIN WIRING: replaceable compiled-artifact journey. The parent's journey drives a
// Note/KV command-line binary against a Redis container; this node ships a manager, not
// a CLI, so the same tier asserts the compiled manager's own interface instead.
import (
	"context"
	"os/exec"
	"strings"
	"testing"
)

func TestCompiledArtifactReportsItsInterface(t *testing.T) {
	ctx := context.Background()
	// #nosec G204 -- the executable is fixed and nothing in the invocation is dynamic.
	output, err := exec.CommandContext(ctx, "../../../dist/manager", "--help").CombinedOutput()
	if err != nil {
		t.Fatalf("run compiled artifact: %v\n%s", err, output)
	}

	// Each flag is a distinct wiring claim, so they are asserted one by one rather than
	// as a single contains-all pass that could not say which half of the manager is gone.
	for _, flag := range []string{"enable-note", "enable-journal", "health-probe-bind-address", "observe"} {
		if !strings.Contains(string(output), flag) {
			t.Fatalf("compiled manager did not report the %s flag\n%s", flag, output)
		}
	}
}
