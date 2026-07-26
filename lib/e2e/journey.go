package e2e

import (
	"context"
	"strconv"
	"strings"
)

// Expectation is what a step's [Result] must satisfy.
//
// It asserts on containment rather than equality because a service's output
// carries timestamps, ids, and durations no test can pin; a journey that
// demanded exact stdout would be rewritten on every release and would stop
// being read.
type Expectation struct {
	// ExitCode is the exit status the step must produce.
	ExitCode int
	// StdoutContains are fragments that must all appear in standard output.
	StdoutContains []string
	// StderrContains are fragments that must all appear in standard error.
	StderrContains []string
	// StdoutExcludes are fragments that must NOT appear in standard output.
	StdoutExcludes []string
}

// Step is one named invocation and the expectation it must meet.
type Step struct {
	// Name identifies the step in reports and failures.
	Name string
	// Invocation is what to run.
	Invocation Invocation
	// Expect is what the result must satisfy.
	Expect Expectation
}

// Journey is an ordered, named sequence of steps.
//
// It is a plain value with no driver bound to it, which is what makes running
// the same journey twice — once compiled, once in-process — the default rather
// than a special case.
type Journey struct {
	// Name identifies the journey in reports and failures.
	Name string
	// Steps run in order; the first failing step ends the run.
	Steps []Step
}

// StepReport records what one step actually produced.
type StepReport struct {
	// Name is the step's name.
	Name string
	// Result is what the driver observed.
	Result Result
}

// Report records a whole journey run against one driver.
type Report struct {
	// Driver is the name of the driver that produced this report.
	Driver string
	// Journey is the name of the journey that was run.
	Journey string
	// Steps are the per-step results, in order.
	Steps []StepReport
}

// RunJourney runs every step of journey against driver in order and returns the
// report.
//
// It stops at the first failing step. A journey is a narrative — step three
// signing in only means something if step two registered — so continuing past a
// failure would produce cascading failures that bury the real one.
//
// An empty journey is a [ProblemJourneyEmpty], never a vacuous green.
func RunJourney(ctx context.Context, driver Driver, journey Journey, problems *Problems) (Report, error) {
	if problems == nil {
		return Report{}, errUnconfigured("problems")
	}
	if driver == nil {
		return Report{}, problems.Raise(
			ProblemDriverUnconfigured,
			"a journey needs a driver",
			map[string]any{"journey": journey.Name},
		)
	}
	if len(journey.Steps) == 0 {
		return Report{}, problems.Raise(
			ProblemJourneyEmpty,
			"a journey with no steps proves nothing",
			map[string]any{"journey": journey.Name},
		)
	}
	report := Report{Driver: driver.Name(), Journey: journey.Name, Steps: make([]StepReport, 0, len(journey.Steps))}
	for index, step := range journey.Steps {
		result, err := driver.Run(ctx, step.Invocation)
		if err != nil {
			return report, err
		}
		report.Steps = append(report.Steps, StepReport{Name: step.Name, Result: result})
		if failure := CheckStep(step, result); failure != nil {
			return report, problems.RaiseFrom(
				ProblemStepFailed,
				failure,
				failure.Error(),
				map[string]any{
					"journey":  journey.Name,
					"driver":   driver.Name(),
					"step":     step.Name,
					"index":    index,
					"exitCode": result.ExitCode,
					"stdout":   result.Stdout,
					"stderr":   result.Stderr,
				},
			)
		}
	}
	return report, nil
}

// CheckStep reports why result misses step's expectation, or nil when it does
// not.
//
// It is exported because it is the assertion a consumer's own driver needs in
// order to behave like the shipped ones, and because the TestHelper's
// assert-the-asserter tier proves it fails on known-bad input.
func CheckStep(step Step, result Result) error {
	if result.ExitCode != step.Expect.ExitCode {
		return &StepMismatchError{
			Step:   step.Name,
			Reason: "exit code " + strconv.Itoa(result.ExitCode) + " is not " + strconv.Itoa(step.Expect.ExitCode),
		}
	}
	for _, fragment := range step.Expect.StdoutContains {
		if !strings.Contains(result.Stdout, fragment) {
			return &StepMismatchError{Step: step.Name, Reason: "stdout is missing " + strconv.Quote(fragment)}
		}
	}
	for _, fragment := range step.Expect.StderrContains {
		if !strings.Contains(result.Stderr, fragment) {
			return &StepMismatchError{Step: step.Name, Reason: "stderr is missing " + strconv.Quote(fragment)}
		}
	}
	for _, fragment := range step.Expect.StdoutExcludes {
		if strings.Contains(result.Stdout, fragment) {
			return &StepMismatchError{Step: step.Name, Reason: "stdout unexpectedly contains " + strconv.Quote(fragment)}
		}
	}
	return nil
}

// StepMismatchError describes one way a result missed its expectation.
//
// It is a distinct error type rather than a formatted string so a consumer can
// errors.As it out of the problem-typed wrapper and read the step name without
// parsing prose.
type StepMismatchError struct {
	// Step is the name of the step that missed.
	Step string
	// Reason is the single, specific way it missed.
	Reason string
}

// Error renders the mismatch.
func (e *StepMismatchError) Error() string {
	return "step " + strconv.Quote(e.Step) + ": " + e.Reason
}

// CompareReports proves two runs of the same journey agree, and is the point of
// shipping two drivers.
//
// It compares step names and exit codes, NOT captured output: an in-process run
// and a subprocess legitimately differ in buffering, colour, and progress
// rendering, so demanding byte-identical streams would make parity useless. What
// must never differ is which steps ran and how each one ended.
func CompareReports(left Report, right Report, problems *Problems) error {
	if problems == nil {
		return errUnconfigured("problems")
	}
	if left.Journey != right.Journey {
		return problems.Raise(
			ProblemParityMismatch,
			"the two reports are for different journeys",
			map[string]any{"left": left.Journey, "right": right.Journey},
		)
	}
	if len(left.Steps) != len(right.Steps) {
		return problems.Raise(
			ProblemParityMismatch,
			"the drivers ran a different number of steps",
			map[string]any{
				"journey":    left.Journey,
				"leftDriver": left.Driver, "leftSteps": len(left.Steps),
				"rightDriver": right.Driver, "rightSteps": len(right.Steps),
			},
		)
	}
	for index, step := range left.Steps {
		other := right.Steps[index]
		if step.Name != other.Name {
			return problems.Raise(
				ProblemParityMismatch,
				"the drivers ran different steps at index "+strconv.Itoa(index),
				map[string]any{"journey": left.Journey, "left": step.Name, "right": other.Name},
			)
		}
		if step.Result.ExitCode != other.Result.ExitCode {
			return problems.Raise(
				ProblemParityMismatch,
				"the drivers disagree on step "+strconv.Quote(step.Name),
				map[string]any{
					"journey":    left.Journey,
					"step":       step.Name,
					"leftDriver": left.Driver, "leftExitCode": step.Result.ExitCode,
					"rightDriver": right.Driver, "rightExitCode": other.Result.ExitCode,
				},
			)
		}
	}
	return nil
}

// RunParity runs journey against both drivers and proves they agree, returning
// both reports.
//
// This is the shape a SIT suite actually wants: one call, one journey, two
// execution models, and a typed failure the moment they diverge.
func RunParity(ctx context.Context, compiled Driver, inProcess Driver, journey Journey, problems *Problems) (Report, Report, error) {
	first, err := RunJourney(ctx, compiled, journey, problems)
	if err != nil {
		return first, Report{}, err
	}
	second, err := RunJourney(ctx, inProcess, journey, problems)
	if err != nil {
		return first, second, err
	}
	return first, second, CompareReports(first, second, problems)
}
