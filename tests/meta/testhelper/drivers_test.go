package testhelper_test

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/AtomiCloud/diene.go-e2e/lib/e2e"
	"github.com/AtomiCloud/diene.go-e2e/testhelper"
)

func TestScriptedDriverAnswersInOrderAndRecordsWhatItWasAsked(t *testing.T) {
	t.Parallel()

	driver := testhelper.NewScriptedDriver(
		"",
		testhelper.ScriptedStep{Result: e2e.Result{ExitCode: 0, Stdout: "first"}},
		testhelper.ScriptedStep{Result: e2e.Result{ExitCode: 5, Stderr: "second"}},
	)
	if driver.Name() != "scripted" {
		t.Fatalf("Name() = %q, want the default label", driver.Name())
	}
	if driver.Remaining() != 2 {
		t.Fatalf("Remaining() = %d, want 2", driver.Remaining())
	}

	first, err := driver.Run(context.Background(), e2e.Invocation{Args: []string{"one"}, Env: map[string]string{"MARKER": "kept"}})
	if err != nil || first.Stdout != "first" {
		t.Fatalf("Run() = %+v, %v, want the first scripted answer", first, err)
	}
	second, err := driver.Run(context.Background(), e2e.Invocation{Args: []string{"two"}})
	if err != nil || second.ExitCode != 5 {
		t.Fatalf("Run() = %+v, %v, want the second scripted answer", second, err)
	}
	if driver.Remaining() != 0 {
		t.Fatalf("Remaining() = %d, want the script consumed", driver.Remaining())
	}

	calls := driver.Calls()
	if len(calls) != 2 || calls[0].Args[0] != "one" || calls[1].Args[0] != "two" {
		t.Fatalf("Calls() = %+v, want both invocations in order", calls)
	}
	if calls[0].Env["MARKER"] != "kept" {
		t.Fatalf("Calls() = %+v, want the recorded environment kept", calls)
	}
	calls[0].Args[0] = "mutated"
	calls[0].Env["MARKER"] = "mutated"
	if driver.Calls()[0].Args[0] != "one" || driver.Calls()[0].Env["MARKER"] != "kept" {
		t.Fatal("Calls() is not a copy, so a caller can rewrite recorded history")
	}
}

func TestScriptedDriverNamesItselfWhenAsked(t *testing.T) {
	t.Parallel()

	if got := testhelper.NewScriptedDriver("compiled").Name(); got != "compiled" {
		t.Fatalf("Name() = %q, want compiled", got)
	}
}

func TestScriptedDriverSurfacesAScriptedFailure(t *testing.T) {
	t.Parallel()

	driver := testhelper.NewScriptedDriver("scripted", testhelper.ScriptedStep{Err: errBoom})
	if _, err := driver.Run(context.Background(), e2e.Invocation{}); !errors.Is(err, errBoom) {
		t.Fatalf("Run() error = %v, want the scripted failure", err)
	}
}

func TestScriptedDriverRefusesToInventAnswers(t *testing.T) {
	t.Parallel()

	driver := testhelper.NewScriptedDriver("scripted")
	_, err := driver.Run(context.Background(), e2e.Invocation{})
	if !errors.Is(err, testhelper.ErrScriptExhausted) {
		t.Fatalf("Run() error = %v, want ErrScriptExhausted rather than a silent zero result", err)
	}
}

func TestEchoEntrypointEchoesArgumentsAndEnvironment(t *testing.T) {
	t.Parallel()

	problems := requireProblems(t)
	driver, err := testhelper.NewEchoDriver(problems)
	if err != nil {
		t.Fatalf("NewEchoDriver() error = %v", err)
	}
	if driver.Name() != "echo" {
		t.Fatalf("Name() = %q, want echo", driver.Name())
	}
	result, err := driver.Run(context.Background(), e2e.Invocation{
		Args: []string{"seed", "--yes"},
		Env:  map[string]string{"B": "two", "A": "one"},
	})
	if err != nil {
		t.Fatalf("Run() error = %v", err)
	}
	if !strings.Contains(result.Stdout, "args: seed --yes") {
		t.Fatalf("stdout = %q, want the arguments echoed", result.Stdout)
	}
	// Sorted, so a journey asserting on the echoed environment is stable.
	if !strings.Contains(result.Stdout, "env: A=one\nenv: B=two") {
		t.Fatalf("stdout = %q, want the environment echoed in a stable order", result.Stdout)
	}
	if !result.Succeeded() {
		t.Fatalf("Run() = %+v, want a clean run", result)
	}
}

func TestEchoEntrypointHonoursTheRequestedExitCode(t *testing.T) {
	t.Parallel()

	problems := requireProblems(t)
	driver, err := testhelper.NewEchoDriver(problems)
	if err != nil {
		t.Fatalf("NewEchoDriver() error = %v", err)
	}
	result, err := driver.Run(context.Background(), e2e.Invocation{
		Env: map[string]string{testhelper.ExitCodeVar: "9"},
	})
	if err != nil {
		t.Fatalf("Run() error = %v", err)
	}
	if result.ExitCode != 9 {
		t.Fatalf("exit code = %d, want 9", result.ExitCode)
	}
	if !strings.Contains(result.Stderr, "exit: 9") {
		t.Fatalf("stderr = %q, want the failure noted", result.Stderr)
	}
}

func TestEchoEntrypointRefusesAnUnparsableExitCode(t *testing.T) {
	t.Parallel()

	problems := requireProblems(t)
	driver, err := testhelper.NewEchoDriver(problems)
	if err != nil {
		t.Fatalf("NewEchoDriver() error = %v", err)
	}
	_, runErr := driver.Run(context.Background(), e2e.Invocation{
		Env: map[string]string{testhelper.ExitCodeVar: "not-a-number"},
	})
	testhelper.AssertHarnessProblem(t, runErr, e2e.ProblemInvocationFailed)
}

func TestEchoEntrypointSurfacesAFailingStream(t *testing.T) {
	t.Parallel()

	blocked := blockedWriter{}
	if _, err := testhelper.EchoEntrypoint(context.Background(), e2e.Invocation{}, blocked, blocked); !errors.Is(err, errBoom) {
		t.Fatalf("EchoEntrypoint() error = %v, want the stream failure surfaced", err)
	}
	if _, err := testhelper.EchoEntrypoint(
		context.Background(),
		e2e.Invocation{Env: map[string]string{"MARKER": "x"}},
		newFailAfter(1), blocked,
	); !errors.Is(err, errBoom) {
		t.Fatalf("EchoEntrypoint() error = %v, want the environment write failure surfaced", err)
	}
	if _, err := testhelper.EchoEntrypoint(
		context.Background(),
		e2e.Invocation{Env: map[string]string{testhelper.ExitCodeVar: "3"}},
		newFailAfter(2), blocked,
	); !errors.Is(err, errBoom) {
		t.Fatalf("EchoEntrypoint() error = %v, want the stderr write failure surfaced", err)
	}
}

func TestNewEchoDriverRefusesAMissingProblemFactory(t *testing.T) {
	t.Parallel()

	if _, err := testhelper.NewEchoDriver(nil); err == nil {
		t.Fatal("NewEchoDriver() error = nil, want the unconfigured refusal")
	}
}

func TestScriptedDriverDrivesARealJourney(t *testing.T) {
	t.Parallel()

	problems := requireProblems(t)
	journey := e2e.Journey{
		Name: "scripted",
		Steps: []e2e.Step{{
			Name:       "only",
			Invocation: e2e.Invocation{Args: []string{"go"}},
			Expect:     e2e.Expectation{ExitCode: 0, StdoutContains: []string{"done"}},
		}},
	}
	driver := testhelper.NewScriptedDriver("scripted", testhelper.ScriptedStep{
		Result: e2e.Result{ExitCode: 0, Stdout: "done"},
	})
	report, err := e2e.RunJourney(context.Background(), driver, journey, problems)
	testhelper.AssertNoHarnessProblem(t, err)
	report = testhelper.RequireReport(t, report, nil)
	testhelper.AssertReport(t, report, journey)
}

// blockedWriter fails every write.
type blockedWriter struct{}

// Write always fails.
func (blockedWriter) Write([]byte) (int, error) {
	return 0, errBoom
}

// failAfter accepts a fixed number of writes and then fails, so each of the
// entrypoint's write sites can be reached in turn.
type failAfter struct {
	remaining *int
}

// newFailAfter builds a writer that fails on the write after count.
func newFailAfter(count int) failAfter {
	remaining := count
	return failAfter{remaining: &remaining}
}

// Write accepts until the budget runs out.
func (w failAfter) Write(payload []byte) (int, error) {
	if *w.remaining == 0 {
		return 0, errBoom
	}
	*w.remaining--
	return len(payload), nil
}
