package e2e

import (
	"context"
	"io"
	"strings"
)

// Entrypoint is a service's composition root expressed as a callable: the same
// function a `main` would delegate to, taking its arguments and environment as
// values and writing to the streams it is handed.
//
// A service that exposes one of these can be driven in-process by
// [InProcessDriver] and as a built binary by [CompiledDriver] with no second
// implementation of the journey.
type Entrypoint func(ctx context.Context, invocation Invocation, stdout io.Writer, stderr io.Writer) (int, error)

// InProcessOptions configures an [InProcessDriver].
type InProcessOptions struct {
	// Label names the driver in reports. Blank falls back to
	// [DefaultInProcessLabel].
	Label string
	// Entrypoint is the composition root under test.
	Entrypoint Entrypoint
	// Environment is the base environment every invocation inherits.
	Environment map[string]string
	// WorkingDirectory is the default directory reported to the entrypoint.
	WorkingDirectory string
	// Problems mints this driver's problem-typed failures.
	Problems *Problems
}

// DefaultInProcessLabel is the driver name an [InProcessDriver] reports when
// its options carry no label.
const DefaultInProcessLabel = "in-process"

// InProcessDriver runs an [Entrypoint] inside the test process, capturing the
// same exit code and streams a compiled run would produce.
//
// It exists for the half of SIT that a subprocess makes expensive: a failing
// step yields a real Go stack, a breakpoint stops in the service's own code, and
// the run costs no process spawn. It is NOT a substitute for the compiled
// driver — it cannot see packaging, flag wiring, or the built artifact's
// environment contract — which is why [CompareReports] exists.
type InProcessDriver struct {
	label            string
	entrypoint       Entrypoint
	environment      map[string]string
	workingDirectory string
	problems         *Problems
}

// NewInProcessDriver creates an in-process driver.
//
// A missing entrypoint or problem factory is a [ProblemDriverUnconfigured]
// rather than a nil-func panic on the first step.
func NewInProcessDriver(options InProcessOptions) (*InProcessDriver, error) {
	if options.Problems == nil {
		return nil, ErrNoProblems
	}
	if options.Entrypoint == nil {
		return nil, options.Problems.Raise(
			ProblemDriverUnconfigured,
			"in-process driver needs an entrypoint",
			map[string]any{"component": "entrypoint"},
		)
	}
	label := options.Label
	if label == "" {
		label = DefaultInProcessLabel
	}
	return &InProcessDriver{
		label:            label,
		entrypoint:       options.Entrypoint,
		environment:      mergedEnvironment(nil, options.Environment),
		workingDirectory: options.WorkingDirectory,
		problems:         options.Problems,
	}, nil
}

// Name identifies the driver in reports and parity failures.
func (d *InProcessDriver) Name() string {
	return d.label
}

// Run calls the entrypoint with invocation's arguments and merged environment,
// capturing whatever it writes to the two streams.
//
// A non-zero exit code is a [Result]. An error returned by the entrypoint is a
// [ProblemInvocationFailed]: the run never reached a verdict, which is a
// different thing from reaching a failing one.
func (d *InProcessDriver) Run(ctx context.Context, invocation Invocation) (Result, error) {
	directory := invocation.WorkingDirectory
	if directory == "" {
		directory = d.workingDirectory
	}
	resolved := Invocation{
		Args:             invocation.Args,
		Env:              mergedEnvironment(d.environment, invocation.Env),
		WorkingDirectory: directory,
	}
	var stdout, stderr strings.Builder
	code, err := d.entrypoint(ctx, resolved, &stdout, &stderr)
	if err != nil {
		return Result{}, d.problems.RaiseFrom(
			ProblemInvocationFailed,
			err,
			"the in-process entrypoint returned an error",
			map[string]any{"driver": d.label},
		)
	}
	return Result{ExitCode: code, Stdout: stdout.String(), Stderr: stderr.String()}, nil
}
