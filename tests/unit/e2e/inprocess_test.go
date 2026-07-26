package e2e_test

import (
	"context"
	"strings"
	"testing"

	"github.com/AtomiCloud/diene.go-e2e/lib/e2e"
)

func TestNewInProcessDriverNeedsAProblemFactory(t *testing.T) {
	t.Parallel()

	_, err := e2e.NewInProcessDriver(e2e.InProcessOptions{Entrypoint: echo})
	if err == nil || err.Error() != "e2e: problems is required" {
		t.Fatalf("NewInProcessDriver() error = %v, want the unconfigured message", err)
	}
}

func TestNewInProcessDriverNeedsAnEntrypoint(t *testing.T) {
	t.Parallel()

	problems := requireProblems(t, samplePortal())
	_, err := e2e.NewInProcessDriver(e2e.InProcessOptions{Problems: problems})
	if got := problemID(t, err); got != e2e.ProblemDriverUnconfigured {
		t.Fatalf("problem id = %q, want %q", got, e2e.ProblemDriverUnconfigured)
	}
	if problemData(t, err)["component"] != "entrypoint" {
		t.Fatalf("problem data = %v, want the entrypoint component", problemData(t, err))
	}
}

func TestInProcessDriverDefaultsItsLabel(t *testing.T) {
	t.Parallel()

	problems := requireProblems(t, samplePortal())
	driver, err := e2e.NewInProcessDriver(e2e.InProcessOptions{Entrypoint: echo, Problems: problems})
	if err != nil {
		t.Fatalf("NewInProcessDriver() error = %v", err)
	}
	if driver.Name() != e2e.DefaultInProcessLabel {
		t.Fatalf("Name() = %q, want %q", driver.Name(), e2e.DefaultInProcessLabel)
	}
}

func TestInProcessDriverCapturesStreamsAndMergesEnvironment(t *testing.T) {
	t.Parallel()

	problems := requireProblems(t, samplePortal())
	driver, err := e2e.NewInProcessDriver(e2e.InProcessOptions{
		Label:            "wired",
		Entrypoint:       echo,
		Environment:      map[string]string{"MARKER": "base"},
		WorkingDirectory: "/srv",
		Problems:         problems,
	})
	if err != nil {
		t.Fatalf("NewInProcessDriver() error = %v", err)
	}
	if driver.Name() != "wired" {
		t.Fatalf("Name() = %q, want wired", driver.Name())
	}
	result, err := driver.Run(context.Background(), e2e.Invocation{
		Args: []string{"seed"},
		Env:  map[string]string{"MARKER": "overlay"},
	})
	if err != nil {
		t.Fatalf("Run() error = %v", err)
	}
	if !strings.Contains(result.Stdout, "args=seed") {
		t.Fatalf("stdout = %q, want the arguments echoed", result.Stdout)
	}
	if !strings.Contains(result.Stdout, "marker=overlay") {
		t.Fatalf("stdout = %q, want the invocation environment to win", result.Stdout)
	}
	if !strings.Contains(result.Stdout, "dir=/srv") {
		t.Fatalf("stdout = %q, want the driver working directory", result.Stdout)
	}
	if !result.Succeeded() {
		t.Fatalf("Run() = %+v, want a clean run", result)
	}
}

func TestInProcessDriverReportsAFailingExitCodeAsAResult(t *testing.T) {
	t.Parallel()

	problems := requireProblems(t, samplePortal())
	driver, err := e2e.NewInProcessDriver(e2e.InProcessOptions{
		Entrypoint: echo,
		Problems:   problems,
	})
	if err != nil {
		t.Fatalf("NewInProcessDriver() error = %v", err)
	}
	result, err := driver.Run(context.Background(), e2e.Invocation{
		Env:              map[string]string{"EXIT": "3"},
		WorkingDirectory: "/case",
	})
	if err != nil {
		t.Fatalf("Run() error = %v, want a failing result rather than an error", err)
	}
	if result.ExitCode != 3 || result.Stderr != "failed" {
		t.Fatalf("Run() = %+v, want exit 3 with stderr failed", result)
	}
}

func TestInProcessDriverReportsAnEntrypointErrorAsAProblem(t *testing.T) {
	t.Parallel()

	problems := requireProblems(t, samplePortal())
	driver, err := e2e.NewInProcessDriver(e2e.InProcessOptions{
		Label:      "broken",
		Entrypoint: failingEntrypoint,
		Problems:   problems,
	})
	if err != nil {
		t.Fatalf("NewInProcessDriver() error = %v", err)
	}
	_, runErr := driver.Run(context.Background(), e2e.Invocation{})
	if got := problemID(t, runErr); got != e2e.ProblemInvocationFailed {
		t.Fatalf("problem id = %q, want %q", got, e2e.ProblemInvocationFailed)
	}
	if problemData(t, runErr)["driver"] != "broken" {
		t.Fatalf("problem data = %v, want the driver named", problemData(t, runErr))
	}
}
