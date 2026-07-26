package e2e

import (
	"context"
	"errors"
	"maps"
	"sort"
)

// Invocation is one call into the system under test: the arguments, the
// environment, the working directory, and the standard input it receives.
//
// It is deliberately transport-free. The same value drives a compiled artifact
// and an in-process entrypoint, which is the whole point: a journey written
// against Invocation cannot accidentally depend on being a subprocess.
type Invocation struct {
	// Args are the arguments passed after the program name.
	Args []string
	// Env are the environment variables set for this invocation, merged over the
	// driver's own base environment.
	Env map[string]string
	// WorkingDirectory is the directory the invocation runs in. Blank means the
	// driver's default.
	WorkingDirectory string
}

// Result is what one [Invocation] produced: the exit code and the captured
// output streams.
type Result struct {
	// ExitCode is the process (or entrypoint) exit status.
	ExitCode int
	// Stdout is everything the invocation wrote to standard output.
	Stdout string
	// Stderr is everything the invocation wrote to standard error.
	Stderr string
}

// Succeeded reports whether the invocation exited zero.
func (r Result) Succeeded() bool {
	return r.ExitCode == 0
}

// Driver runs invocations against the system under test.
//
// Two implementations ship here — [CompiledDriver] and [InProcessDriver] — and
// a consumer is free to add a third (a remote driver against a deployed preview
// service, say) because a journey only ever sees this seam.
type Driver interface {
	// Name identifies the driver in reports and parity failures.
	Name() string
	// Run carries out invocation and reports what it produced. A non-nil error
	// means the invocation could not be carried out at all; a failing exit code
	// is a Result, not an error.
	Run(ctx context.Context, invocation Invocation) (Result, error)
}

// errUnconfigured reports a seam the harness cannot substitute for and cannot
// describe as a problem either, because the problem factory is the seam that is
// missing. It is the only non-problem error this library raises.
func errUnconfigured(component string) error {
	return errors.New("e2e: " + component + " is required")
}

// mergedEnvironment overlays an invocation's environment onto a driver's base
// environment, so a journey can override one variable without restating the
// whole environment contract.
func mergedEnvironment(base map[string]string, overlay map[string]string) map[string]string {
	merged := make(map[string]string, len(base)+len(overlay))
	maps.Copy(merged, base)
	maps.Copy(merged, overlay)
	return merged
}

// sortedKeys returns a map's keys in a stable order, so problem data and
// rendered environments never depend on Go's map iteration order.
func sortedKeys[Value any](entries map[string]Value) []string {
	keys := make([]string, 0, len(entries))
	for key := range entries {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}
