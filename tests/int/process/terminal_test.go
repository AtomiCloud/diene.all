package process_test

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/AtomiCloud/diene.go-e2e/adapters/process"
	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
)

// These are integration tests: they run REAL processes through the real process
// table. The unit tier drives the compiled-artifact driver against the
// interfaces sibling's in-memory terminal, so this is the only place the binding
// itself is proven, and it is proven against actual subprocesses rather than a
// second mock.

func command(executable string, args ...string) interfaces.TerminalCommand {
	return interfaces.NewTerminalCommand(executable, args, nil, nil, false, false)
}

func TestRunCapturesStdoutAndExitZero(t *testing.T) {
	t.Parallel()

	terminal := process.NewTerminal(process.TerminalOptions{})
	output, err := terminal.Run(context.Background(), command("printf", "hello"))
	if err != nil {
		t.Fatalf("Run() error = %v", err)
	}
	if output.ExitCode != 0 {
		t.Fatalf("exit code = %d, want 0", output.ExitCode)
	}
	if output.Stdout != "hello" {
		t.Fatalf("stdout = %q, want hello", output.Stdout)
	}
	if output.Stderr != "" {
		t.Fatalf("stderr = %q, want it empty", output.Stderr)
	}
}

func TestRunReportsANonZeroExitAsOutputNotAnError(t *testing.T) {
	t.Parallel()

	terminal := process.NewTerminal(process.TerminalOptions{Shell: "/bin/sh"})
	output, err := terminal.Run(context.Background(), interfaces.NewTerminalCommand(
		"printf 'out'; printf 'err' >&2; exit 3", nil, nil, nil, false, true,
	))
	if err != nil {
		t.Fatalf("Run() error = %v, want a failing exit reported as output", err)
	}
	if output.ExitCode != 3 {
		t.Fatalf("exit code = %d, want 3", output.ExitCode)
	}
	if output.Stdout != "out" || output.Stderr != "err" {
		t.Fatalf("output = %+v, want both streams captured", output)
	}
}

func TestRunHonoursTheWorkingDirectory(t *testing.T) {
	t.Parallel()

	directory := t.TempDir()
	resolved, err := filepath.EvalSymlinks(directory)
	if err != nil {
		t.Fatalf("EvalSymlinks() error = %v", err)
	}
	terminal := process.NewTerminal(process.TerminalOptions{Shell: "/bin/sh"})
	output, runErr := terminal.Run(context.Background(), interfaces.NewTerminalCommand(
		"pwd", nil, &resolved, nil, false, true,
	))
	if runErr != nil {
		t.Fatalf("Run() error = %v", runErr)
	}
	if strings.TrimSpace(output.Stdout) != resolved {
		t.Fatalf("stdout = %q, want the working directory %q", output.Stdout, resolved)
	}
}

func TestRunBuildsAHermeticEnvironmentByDefault(t *testing.T) {
	t.Setenv("E2E_PARENT_MARKER", "parent")
	terminal := process.NewTerminal(process.TerminalOptions{Shell: "/bin/sh"})
	output, err := terminal.Run(context.Background(), interfaces.NewTerminalCommand(
		"printf '%s|%s' \"$E2E_OWN_MARKER\" \"$E2E_PARENT_MARKER\"",
		nil, nil, map[string]string{"E2E_OWN_MARKER": "own"}, false, true,
	))
	if err != nil {
		t.Fatalf("Run() error = %v", err)
	}
	if output.Stdout != "own|" {
		t.Fatalf("stdout = %q, want the parent environment excluded", output.Stdout)
	}
}

func TestRunInheritsTheParentEnvironmentWhenAsked(t *testing.T) {
	t.Setenv("E2E_PARENT_MARKER", "parent")
	terminal := process.NewTerminal(process.TerminalOptions{Shell: "/bin/sh"})
	output, err := terminal.Run(context.Background(), interfaces.NewTerminalCommand(
		"printf '%s|%s' \"$E2E_OWN_MARKER\" \"$E2E_PARENT_MARKER\"",
		nil, nil, map[string]string{"E2E_OWN_MARKER": "own"}, true, true,
	))
	if err != nil {
		t.Fatalf("Run() error = %v", err)
	}
	if output.Stdout != "own|parent" {
		t.Fatalf("stdout = %q, want both the override and the inherited value", output.Stdout)
	}
}

func TestRunLetsAnOverrideBeatTheInheritedValue(t *testing.T) {
	t.Setenv("E2E_SHARED_MARKER", "parent")
	terminal := process.NewTerminal(process.TerminalOptions{Shell: "/bin/sh"})
	output, err := terminal.Run(context.Background(), interfaces.NewTerminalCommand(
		"printf '%s' \"$E2E_SHARED_MARKER\"",
		nil, nil, map[string]string{"E2E_SHARED_MARKER": "override"}, true, true,
	))
	if err != nil {
		t.Fatalf("Run() error = %v", err)
	}
	if output.Stdout != "override" {
		t.Fatalf("stdout = %q, want the override to win", output.Stdout)
	}
}

func TestRunRefusesACommandWithNothingToRun(t *testing.T) {
	t.Parallel()

	terminal := process.NewTerminal(process.TerminalOptions{})
	_, err := terminal.Run(context.Background(), command("   "))
	if !errors.Is(err, process.ErrNoExecutable) {
		t.Fatalf("Run() error = %v, want ErrNoExecutable", err)
	}
}

func TestRunSurfacesAProcessThatNeverStarted(t *testing.T) {
	t.Parallel()

	terminal := process.NewTerminal(process.TerminalOptions{})
	output, err := terminal.Run(context.Background(), command(filepath.Join(t.TempDir(), "absent-binary")))
	if err == nil {
		t.Fatalf("Run() error = nil, want the start failure surfaced")
	}
	var execErr *exec.Error
	if !errors.As(err, &execErr) && !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("Run() error = %v, want an exec failure", err)
	}
	if output.ExitCode != 0 {
		t.Fatalf("output = %+v, want the zero value when nothing ran", output)
	}
}

func TestRunHonoursACancelledContext(t *testing.T) {
	t.Parallel()

	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	terminal := process.NewTerminal(process.TerminalOptions{})
	if _, err := terminal.Run(ctx, command("printf", "never")); err == nil {
		t.Fatalf("Run() error = nil, want the cancelled context to stop the run")
	}
}

func TestShellModeFallsBackThroughTheEnvironmentToPosix(t *testing.T) {
	t.Setenv(process.ShellEnvVar, "/bin/sh")
	fromEnvironment := process.NewTerminal(process.TerminalOptions{})
	output, err := fromEnvironment.Run(context.Background(), interfaces.NewTerminalCommand(
		"printf", []string{"from-env"}, nil, nil, false, true,
	))
	if err != nil || output.Stdout != "from-env" {
		t.Fatalf("Run() = %+v, %v, want the SHELL interpreter used", output, err)
	}

	t.Setenv(process.ShellEnvVar, "")
	fallback := process.NewTerminal(process.TerminalOptions{})
	output, err = fallback.Run(context.Background(), interfaces.NewTerminalCommand(
		"printf", []string{"from-default"}, nil, nil, false, true,
	))
	if err != nil || output.Stdout != "from-default" {
		t.Fatalf("Run() = %+v, %v, want %q used", output, err, process.DefaultShell)
	}
}

func TestEnvironRendersInheritedThenOverridesInAStableOrder(t *testing.T) {
	t.Parallel()

	got := process.Environ(map[string]string{"B": "two", "A": "one", "C": "three"}, []string{"INHERITED=yes"})
	want := []string{"INHERITED=yes", "A=one", "B=two", "C=three"}
	if len(got) != len(want) {
		t.Fatalf("Environ() = %v, want %v", got, want)
	}
	for index, entry := range want {
		if got[index] != entry {
			t.Fatalf("Environ() = %v, want %v", got, want)
		}
	}
	if len(process.Environ(nil, nil)) != 0 {
		t.Fatalf("Environ(nil, nil) = %v, want nothing", process.Environ(nil, nil))
	}
}
