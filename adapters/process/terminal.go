package process

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"slices"
	"strings"

	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
)

// DefaultShell is the interpreter a shell-mode command runs under when the
// environment names none.
const DefaultShell = "/bin/sh"

// ShellEnvVar is the environment variable consulted for the shell-mode
// interpreter.
const ShellEnvVar = "SHELL"

// TerminalOptions configures a [Terminal].
type TerminalOptions struct {
	// Shell overrides the interpreter used for shell-mode commands. Blank
	// consults [ShellEnvVar] and then falls back to [DefaultShell].
	Shell string
}

// Terminal runs real operating-system processes and satisfies
// [interfaces.Terminal].
//
// It is a value type with no mutable state, so one instance is safe to share
// across a whole suite.
type Terminal struct {
	shell string
}

// NewTerminal creates a terminal bound to the real process table.
func NewTerminal(options TerminalOptions) Terminal {
	return Terminal{shell: options.Shell}
}

// Run executes command and reports its exit code and captured streams.
//
// A NON-ZERO EXIT IS NOT AN ERROR. That is the whole contract: a harness driving
// a CLI needs to assert on failing exit codes, so only a failure to run the
// process at all — a missing binary, an unreadable working directory, a
// cancelled context — surfaces as an error.
func (t Terminal) Run(ctx context.Context, command interfaces.TerminalCommand) (interfaces.TerminalOutput, error) {
	executable, args, err := t.resolve(command)
	if err != nil {
		return interfaces.TerminalOutput{}, err
	}
	// Running a caller-named executable IS this adapter's entire purpose: it is
	// the harness binding for the family terminal seam, and every path into it is
	// a test author naming the artifact they built. There is nothing to sanitise.
	process := exec.CommandContext(ctx, executable, args...) //nolint:gosec // the seam exists to run a named executable
	if command.WorkingDirectory != nil {
		process.Dir = *command.WorkingDirectory
	}
	process.Env = Environ(command.Environment, t.inherited(command))
	var stdout, stderr strings.Builder
	process.Stdout = &stdout
	process.Stderr = &stderr
	runErr := process.Run()
	output := interfaces.TerminalOutput{
		ExitCode: exitCode(process),
		Stdout:   stdout.String(),
		Stderr:   stderr.String(),
	}
	if runErr == nil {
		return output, nil
	}
	var exitErr *exec.ExitError
	if errors.As(runErr, &exitErr) {
		return output, nil
	}
	return interfaces.TerminalOutput{}, runErr
}

// inherited returns the parent environment when the command asked to keep it,
// and nothing when it asked for a hermetic one.
func (Terminal) inherited(command interfaces.TerminalCommand) []string {
	if command.IncludeParentEnvironment {
		return os.Environ()
	}
	return nil
}

// exitCode reads a finished process's status, tolerating a process that never
// started and therefore has no status at all.
func exitCode(process *exec.Cmd) int {
	if process.ProcessState == nil {
		return -1
	}
	return process.ProcessState.ExitCode()
}

// resolve turns a command into the executable and arguments the process table
// receives, honouring shell mode.
func (t Terminal) resolve(command interfaces.TerminalCommand) (string, []string, error) {
	if strings.TrimSpace(command.Executable) == "" {
		return "", nil, ErrNoExecutable
	}
	if !command.RunInShell {
		return command.Executable, command.Args, nil
	}
	script := strings.Join(append([]string{command.Executable}, command.Args...), " ")
	return t.interpreter(), []string{"-c", script}, nil
}

// interpreter picks the shell-mode interpreter: the configured one, then the
// caller's own SHELL, then the POSIX fallback.
func (t Terminal) interpreter() string {
	if t.shell != "" {
		return t.shell
	}
	if shell := os.Getenv(ShellEnvVar); shell != "" {
		return shell
	}
	return DefaultShell
}

// ErrNoExecutable reports a command with nothing to run.
var ErrNoExecutable = errors.New("process: a terminal command needs an executable")

// Environ renders the environment a process receives: inherited first, then the
// overrides that win over it.
//
// Overrides are applied in sorted order so the rendered environment is
// deterministic, which matters when a failing SIT run is being compared against
// a passing one.
func Environ(overrides map[string]string, inherited []string) []string {
	environ := make([]string, 0, len(inherited)+len(overrides))
	environ = append(environ, inherited...)
	keys := make([]string, 0, len(overrides))
	for key := range overrides {
		keys = append(keys, key)
	}
	slices.Sort(keys)
	for _, key := range keys {
		environ = append(environ, key+"="+overrides[key])
	}
	return environ
}
