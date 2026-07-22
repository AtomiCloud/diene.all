package interfaces

import (
	"context"
	"maps"
)

// TerminalCommand is one process invocation requested through Terminal.
// Construct it with NewTerminalCommand to take immutable snapshots of slices
// and maps supplied by the caller.
type TerminalCommand struct {
	// Executable is the program to launch.
	Executable string
	// Args are the program arguments, excluding Executable.
	Args []string
	// WorkingDirectory is absent when the implementation should keep its cwd.
	WorkingDirectory *string
	// Environment contains process-specific environment overrides.
	Environment map[string]string
	// IncludeParentEnvironment controls whether host variables are inherited.
	IncludeParentEnvironment bool
	// RunInShell requests execution via an implementation-selected shell.
	RunInShell bool
}

// NewTerminalCommand creates a command with cloned inputs.
func NewTerminalCommand(executable string, args []string, workingDirectory *string, environment map[string]string, includeParentEnvironment bool, runInShell bool) TerminalCommand {
	command := TerminalCommand{
		Executable:               executable,
		Args:                     append([]string(nil), args...),
		Environment:              cloneStringMap(environment),
		IncludeParentEnvironment: includeParentEnvironment,
		RunInShell:               runInShell,
	}
	if workingDirectory != nil {
		copied := *workingDirectory
		command.WorkingDirectory = &copied
	}
	return command
}

// Clone returns a command with independently owned mutable fields.
func (c TerminalCommand) Clone() TerminalCommand {
	return NewTerminalCommand(c.Executable, c.Args, c.WorkingDirectory, c.Environment, c.IncludeParentEnvironment, c.RunInShell)
}

// TerminalOutput is captured output from a completed terminal invocation.
type TerminalOutput struct {
	// ExitCode is the child process exit code.
	ExitCode int
	// Stdout is captured standard output.
	Stdout string
	// Stderr is captured standard error.
	Stderr string
}

// Succeeded reports whether the child exited with code zero.
func (o TerminalOutput) Succeeded() bool { return o.ExitCode == 0 }

// Terminal is a process-execution boundary. A non-zero child exit code is a
// successful TerminalOutput; only a launch failure is returned as an error.
type Terminal interface {
	// Run executes command.
	Run(ctx context.Context, command TerminalCommand) (TerminalOutput, error)
}

func cloneStringMap(values map[string]string) map[string]string {
	if values == nil {
		return map[string]string{}
	}
	return maps.Clone(values)
}
