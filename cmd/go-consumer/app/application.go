// Package app is the importable go-consumer composition root. The operating
// system entry and the in-process SIT driver call the same Application.Execute
// method, so flag parsing, configuration, and lifecycle behavior cannot drift.
package app

import (
	"context"
	"errors"
	"fmt"
	"io"
	"strings"
	"sync"

	"github.com/AtomiCloud/diene.go-e2e/lib/e2e"
	"github.com/spf13/cobra"
)

const (
	// ExitSuccess is returned after a command finishes successfully.
	ExitSuccess = 0
	// ExitRuntime is returned when configuration or runtime work fails.
	ExitRuntime = 1
	// ExitUsage is returned when the command line is invalid.
	ExitUsage = 2
)

// Invocation is the shared compiled/in-process invocation contract.
type Invocation = e2e.Invocation

// Options supplies process-owned values without introducing package globals.
type Options struct {
	Name string
	PID  int
}

// Application owns CLI construction and the process-wide telemetry
// registration decision across repeated in-process invocations.
type Application struct {
	name             string
	pid              int
	registrationMu   sync.Mutex
	globalRegistered bool
}

// New constructs a reusable command application.
func New(options Options) *Application {
	name := strings.TrimSpace(options.Name)
	if name == "" {
		name = "consumer"
	}
	return &Application{name: name, pid: options.PID}
}

type runtimeFailure struct{ cause error }

func (failure runtimeFailure) Error() string { return failure.cause.Error() }
func (failure runtimeFailure) Unwrap() error { return failure.cause }

// Execute runs one invocation. Expected command failures are represented by
// exit codes and stderr, leaving the error return for a broken driver contract.
func (a *Application) Execute(
	ctx context.Context,
	invocation Invocation,
	stdout io.Writer,
	stderr io.Writer,
) (int, error) {
	if stdout == nil || stderr == nil {
		return ExitRuntime, errors.New("application: stdout and stderr are required")
	}
	root, err := repositoryRoot(invocation)
	if err != nil {
		_, _ = fmt.Fprintln(stderr, err)
		return ExitRuntime, nil
	}
	var landscape string
	command := &cobra.Command{
		Use:           a.name,
		Short:         "Config-driven Redis streams worker consumer",
		SilenceErrors: true,
		SilenceUsage:  true,
		Args:          cobra.NoArgs,
		RunE: func(_ *cobra.Command, _ []string) error {
			return errors.New("a command is required: worker, db-init, or health")
		},
	}
	command.CompletionOptions.DisableDefaultCmd = true
	command.SetOut(stdout)
	command.SetErr(stderr)
	command.SetArgs(invocation.Args)
	command.PersistentFlags().StringVar(&landscape, "landscape", "", "select a sparse landscape overlay")
	command.AddCommand(
		a.workerCommand(root, invocation, stdout, &landscape),
		a.dbInitCommand(root, invocation, stdout, &landscape),
		a.healthCommand(root, invocation, stdout, &landscape),
	)
	if executeErr := command.ExecuteContext(ctx); executeErr != nil {
		_, _ = fmt.Fprintln(stderr, executeErr)
		var runtimeErr runtimeFailure
		if errors.As(executeErr, &runtimeErr) {
			return ExitRuntime, nil
		}
		return ExitUsage, nil
	}
	return ExitSuccess, nil
}

func wrapRuntime(run func(context.Context) error) func(*cobra.Command, []string) error {
	return func(command *cobra.Command, _ []string) error {
		if err := run(command.Context()); err != nil {
			return runtimeFailure{cause: err}
		}
		return nil
	}
}
