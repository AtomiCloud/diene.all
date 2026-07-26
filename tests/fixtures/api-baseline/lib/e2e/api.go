// Package e2e is the sealed v1.0.0 API baseline `gorelease` compares the
// current public surface against.
//
// It is DELIBERATELY a subset, and deliberately dependency-free. The API-compat
// validator rewrites this fixture's go.mod to module-plus-go-version before
// zipping it into a local proxy, so a baseline that imported a published sibling
// could not be loaded at all — and every package absent from the baseline is a
// compatible ADDITION, which is exactly the right verdict for a first release.
//
// What it does pin is the harness's load-bearing value types and the seam every
// journey is written against. Renaming a field here, or changing the shape of
// [Driver], breaks a consumer's own drivers and assertions, so those are the
// things v1 must not move.
package e2e

import (
	"context"
	"io"
)

// ProblemVersion is the contract version segment of every harness problem type
// URI.
const ProblemVersion = "v1"

// Harness problem ids.
const (
	ProblemDriverUnconfigured = "driver-unconfigured"
	ProblemArtifactMissing    = "artifact-missing"
	ProblemInvocationFailed   = "invocation-failed"
	ProblemJourneyEmpty       = "journey-empty"
	ProblemStepFailed         = "step-failed"
	ProblemParityMismatch     = "driver-parity-mismatch"
	ProblemTargetIncomplete   = "preview-target-incomplete"
	ProblemTargetUnreadable   = "preview-target-unreadable"
	ProblemFixtureInvalid     = "fixture-invalid"
	ProblemFixtureUnwritable  = "fixture-unwritable"
)

// Driver labels.
const (
	DefaultCompiledLabel  = "compiled"
	DefaultInProcessLabel = "in-process"
)

// Invocation is one call into the system under test.
type Invocation struct {
	Args             []string
	Env              map[string]string
	WorkingDirectory string
}

// Result is what one invocation produced.
type Result struct {
	ExitCode int
	Stdout   string
	Stderr   string
}

// Succeeded reports whether the invocation exited zero.
func (Result) Succeeded() bool { return false }

// Driver runs invocations against the system under test.
type Driver interface {
	Name() string
	Run(ctx context.Context, invocation Invocation) (Result, error)
}

// Entrypoint is a service's composition root expressed as a callable.
type Entrypoint func(ctx context.Context, invocation Invocation, stdout io.Writer, stderr io.Writer) (int, error)

// Expectation is what a step's result must satisfy.
type Expectation struct {
	ExitCode       int
	StdoutContains []string
	StderrContains []string
	StdoutExcludes []string
}

// Step is one named invocation and the expectation it must meet.
type Step struct {
	Name       string
	Invocation Invocation
	Expect     Expectation
}

// Journey is an ordered, named sequence of steps.
type Journey struct {
	Name  string
	Steps []Step
}

// StepReport records what one step actually produced.
type StepReport struct {
	Name   string
	Result Result
}

// Report records a whole journey run against one driver.
type Report struct {
	Driver  string
	Journey string
	Steps   []StepReport
}

// StepMismatchError describes one way a result missed its expectation.
type StepMismatchError struct {
	Step   string
	Reason string
}

// Error renders the mismatch.
func (*StepMismatchError) Error() string { return "" }

// CheckStep reports why result misses step's expectation.
func CheckStep(Step, Result) error { return nil }
