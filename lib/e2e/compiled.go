package e2e

import (
	"context"

	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
)

// CompiledOptions configures a [CompiledDriver].
type CompiledOptions struct {
	// Label names the driver in reports. Blank falls back to
	// [DefaultCompiledLabel].
	Label string
	// Artifact is the path of the built binary under test.
	Artifact string
	// Terminal executes the artifact. The real binding lives in
	// adapters/process; the interfaces sibling's in-memory terminal drives the
	// harness's own tests.
	Terminal interfaces.Terminal
	// Filesystem is consulted to prove the artifact exists before the first run.
	// Optional: a nil filesystem skips the existence check.
	Filesystem interfaces.Vfs
	// Environment is the base environment every invocation inherits.
	Environment map[string]string
	// WorkingDirectory is the default directory invocations run in.
	WorkingDirectory string
	// Problems mints this driver's problem-typed failures.
	Problems *Problems
}

// DefaultCompiledLabel is the driver name a [CompiledDriver] reports when its
// options carry no label.
const DefaultCompiledLabel = "compiled"

// CompiledDriver drives a COMPILED ARTIFACT: it runs the built binary the way a
// deployment would, through the [interfaces.Terminal] seam.
//
// This is the driver that catches what an in-process run structurally cannot —
// a flag the binary never wired up, an environment variable the built artifact
// reads under a different name, a working directory assumption. It is therefore
// the SIT driver of record against the Garden preview environment.
type CompiledDriver struct {
	label            string
	artifact         string
	terminal         interfaces.Terminal
	filesystem       interfaces.Vfs
	environment      map[string]string
	workingDirectory string
	problems         *Problems
}

// NewCompiledDriver creates a compiled-artifact driver.
//
// It refuses a driver it could not honestly run: a blank artifact path, a
// missing terminal, or a missing problem factory is a
// [ProblemDriverUnconfigured] rather than a nil-pointer panic three journeys
// later.
func NewCompiledDriver(options CompiledOptions) (*CompiledDriver, error) {
	if options.Problems == nil {
		return nil, ErrNoProblems
	}
	if options.Artifact == "" {
		return nil, options.Problems.Raise(
			ProblemDriverUnconfigured,
			"compiled driver needs an artifact path",
			map[string]any{"component": "artifact"},
		)
	}
	if options.Terminal == nil {
		return nil, options.Problems.Raise(
			ProblemDriverUnconfigured,
			"compiled driver needs a terminal seam",
			map[string]any{"component": "terminal"},
		)
	}
	label := options.Label
	if label == "" {
		label = DefaultCompiledLabel
	}
	return &CompiledDriver{
		label:            label,
		artifact:         options.Artifact,
		terminal:         options.Terminal,
		filesystem:       options.Filesystem,
		environment:      mergedEnvironment(nil, options.Environment),
		workingDirectory: options.WorkingDirectory,
		problems:         options.Problems,
	}, nil
}

// Name identifies the driver in reports and parity failures.
func (d *CompiledDriver) Name() string {
	return d.label
}

// Artifact returns the path of the binary this driver runs, so a report or a
// failure message can name the exact thing that was exercised.
func (d *CompiledDriver) Artifact() string {
	return d.artifact
}

// Run executes the artifact with invocation's arguments, environment, and
// working directory.
//
// A non-zero exit code is a [Result], not an error — that is the journey's
// business. An error means the artifact could not be run at all.
func (d *CompiledDriver) Run(ctx context.Context, invocation Invocation) (Result, error) {
	if err := d.requireArtifact(ctx); err != nil {
		return Result{}, err
	}
	directory := invocation.WorkingDirectory
	if directory == "" {
		directory = d.workingDirectory
	}
	command := interfaces.NewTerminalCommand(
		d.artifact,
		invocation.Args,
		optionalDirectory(directory),
		mergedEnvironment(d.environment, invocation.Env),
		true,
		false,
	)
	output, err := d.terminal.Run(ctx, command)
	if err != nil {
		return Result{}, d.problems.RaiseFrom(
			ProblemInvocationFailed,
			err,
			"the compiled artifact could not be executed",
			map[string]any{"driver": d.label, "artifact": d.artifact},
		)
	}
	return Result{ExitCode: output.ExitCode, Stdout: output.Stdout, Stderr: output.Stderr}, nil
}

// requireArtifact proves the binary is on disk before the terminal reports its
// absence as an ordinary non-zero exit, which would read as a journey failure
// rather than the harness misconfiguration it is.
func (d *CompiledDriver) requireArtifact(ctx context.Context) error {
	if d.filesystem == nil {
		return nil
	}
	exists, err := d.filesystem.Exists(ctx, d.artifact)
	if err != nil {
		return d.problems.RaiseFrom(
			ProblemArtifactMissing,
			err,
			"the compiled artifact could not be inspected",
			map[string]any{"artifact": d.artifact},
		)
	}
	if !exists {
		return d.problems.Raise(
			ProblemArtifactMissing,
			"the compiled artifact does not exist",
			map[string]any{"artifact": d.artifact},
		)
	}
	return nil
}

// optionalDirectory renders a blank working directory as the absent value the
// terminal contract expects, rather than as an empty path.
func optionalDirectory(directory string) *string {
	if directory == "" {
		return nil
	}
	return &directory
}
