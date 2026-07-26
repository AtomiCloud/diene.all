package e2e

import (
	"context"
	"errors"
	"maps"
)

// Invocation is one call into the system under test: the arguments, the
// environment, and the working directory it runs with.
//
// It is deliberately transport-free. The same value drives a compiled artifact
// and an in-process entrypoint, which is the whole point: a journey written
// against Invocation cannot accidentally depend on being a subprocess. It
// carries no standard input, because the family's [interfaces.Terminal] seam
// does not, and a field only one driver could honour would make parity a lie.
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

// ErrNoProblems reports a call made without the problem factory.
//
// It is the one failure this library cannot describe in RFC 9457 terms, because
// the thing that mints those envelopes is exactly what is missing.
var ErrNoProblems = errors.New("e2e: problems is required")

// mergedEnvironment overlays an invocation's environment onto a driver's base
// environment, so a journey can override one variable without restating the
// whole environment contract.
func mergedEnvironment(base map[string]string, overlay map[string]string) map[string]string {
	merged := make(map[string]string, len(base)+len(overlay))
	maps.Copy(merged, base)
	maps.Copy(merged, overlay)
	return merged
}
