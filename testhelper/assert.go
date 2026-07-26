package testhelper

import (
	"errors"
	"strconv"
	"strings"

	"github.com/AtomiCloud/diene.go-e2e/lib/e2e"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

// TestingT is the slice of *testing.T the harness assertions need.
//
// It is an interface rather than *testing.T so the helpers can be proven to
// FAIL, which a helper that only ever ran against a real *testing.T could not
// be: the meta tier hands them a recorder and asserts on what they reported.
type TestingT interface {
	// Helper marks the caller as a test helper.
	Helper()
	// Fatalf reports a fatal failure.
	Fatalf(format string, args ...any)
}

// CheckResult reports why a result misses want, or nil when it matches.
//
// Only the fields want actually sets are compared: a zero expected exit code
// with no output fragments asserts a clean run and nothing more, so a caller
// never has to restate output it does not care about.
func CheckResult(actual e2e.Result, want e2e.Expectation) error {
	return e2e.CheckStep(e2e.Step{Name: "result", Invocation: e2e.Invocation{}, Expect: want}, actual)
}

// AssertResult fails the test unless actual satisfies want.
func AssertResult(t TestingT, actual e2e.Result, want e2e.Expectation) {
	t.Helper()
	if err := CheckResult(actual, want); err != nil {
		t.Fatalf("unexpected result: %v", err)
	}
}

// CheckStep reports why a step's observed result misses its own expectation.
func CheckStep(step e2e.Step, actual e2e.Result) error {
	return e2e.CheckStep(step, actual)
}

// AssertStep fails the test unless a step's observed result meets its
// expectation.
func AssertStep(t TestingT, step e2e.Step, actual e2e.Result) {
	t.Helper()
	if err := e2e.CheckStep(step, actual); err != nil {
		t.Fatalf("unexpected step result: %v", err)
	}
}

// CheckReport reports why a report does not describe the journey it should.
//
// It proves the report covers every step of journey, in order, which is the
// assertion that catches a driver that silently skipped one — the failure mode
// a per-step assertion structurally cannot see.
func CheckReport(actual e2e.Report, journey e2e.Journey) error {
	if actual.Journey != journey.Name {
		return errors.New("report is for journey " + strconv.Quote(actual.Journey) +
			", want " + strconv.Quote(journey.Name))
	}
	if len(actual.Steps) != len(journey.Steps) {
		return errors.New("report covers " + strconv.Itoa(len(actual.Steps)) +
			" steps, want " + strconv.Itoa(len(journey.Steps)))
	}
	for index, step := range journey.Steps {
		observed := actual.Steps[index]
		if observed.Name != step.Name {
			return errors.New("step " + strconv.Itoa(index) + " is " + strconv.Quote(observed.Name) +
				", want " + strconv.Quote(step.Name))
		}
		if err := e2e.CheckStep(step, observed.Result); err != nil {
			return err
		}
	}
	return nil
}

// AssertReport fails the test unless actual describes a complete, passing run
// of journey.
func AssertReport(t TestingT, actual e2e.Report, journey e2e.Journey) {
	t.Helper()
	if err := CheckReport(actual, journey); err != nil {
		t.Fatalf("unexpected report: %v", err)
	}
}

// CheckHarnessProblem reports why err is not the harness problem id names.
func CheckHarnessProblem(err error, id string) (problem.Problem, error) {
	if err == nil {
		return problem.Problem{}, errors.New("expected harness problem " + strconv.Quote(id) + ", got no error")
	}
	var typed *problem.Error
	if !errors.As(err, &typed) {
		return problem.Problem{}, errors.New("expected harness problem " + strconv.Quote(id) +
			", got a plain error: " + err.Error())
	}
	if !strings.HasSuffix(typed.Problem.Type, "/"+id) {
		return typed.Problem, errors.New("expected harness problem " + strconv.Quote(id) +
			", got type " + strconv.Quote(typed.Problem.Type))
	}
	return typed.Problem, nil
}

// AssertHarnessProblem fails the test unless err is the harness problem id
// names, and returns the envelope for further assertions.
func AssertHarnessProblem(t TestingT, err error, id string) problem.Problem {
	t.Helper()
	envelope, failure := CheckHarnessProblem(err, id)
	if failure != nil {
		t.Fatalf("unexpected error: %v", failure)
	}
	return envelope
}

// AssertNoHarnessProblem fails the test when err is set.
func AssertNoHarnessProblem(t TestingT, err error) {
	t.Helper()
	if err != nil {
		t.Fatalf("unexpected harness failure: %v", err)
	}
}

// RequireReport fails the test unless a journey run succeeded, and returns its
// report.
func RequireReport(t TestingT, report e2e.Report, err error) e2e.Report {
	t.Helper()
	if err != nil {
		t.Fatalf("journey did not complete: %v", err)
	}
	return report
}

// SampleProblems builds a harness problem factory on the shared sample error
// portal, so a consumer's first test needs no portal of its own.
func SampleProblems() (*e2e.Problems, error) {
	return e2e.NewProblems(ProblemSampleErrorPortal())
}
