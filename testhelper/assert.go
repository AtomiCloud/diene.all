package testhelper

import (
	"errors"
	"fmt"
	"maps"
	"reflect"

	"github.com/AtomiCloud/diene.go-api-engine/lib/apiengine"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

// TestingT is the slice of *testing.T the assertions here use.
//
// Taking an interface rather than *testing.T keeps this package importable
// from a consumer's own helper layer and lets the assertions be proven against
// a recording double in the meta tier — an assertion nobody has watched fail is
// an assertion nobody has tested.
type TestingT interface {
	Helper()
	Errorf(format string, args ...any)
}

// CheckProblem reports whether err carries the expected problem envelope,
// returning the envelope it found.
//
// It is the check half of [AssertProblem], separated so a consumer can compose
// it into its own assertions without a *testing.T in hand.
func CheckProblem(err error, want ProblemOptions) (problem.Problem, error) {
	var carried *problem.Error
	if !errors.As(err, &carried) {
		return problem.Problem{}, fmt.Errorf("expected a problem-typed error, got %w", err)
	}
	actual := carried.Problem

	if want.Type != "" && actual.Type != want.Type {
		return actual, fmt.Errorf("problem type: want %q, got %q", want.Type, actual.Type)
	}
	if want.Title != "" && actual.Title != want.Title {
		return actual, fmt.Errorf("problem title: want %q, got %q", want.Title, actual.Title)
	}
	if want.Status != 0 && actual.Status != want.Status {
		return actual, fmt.Errorf("problem status: want %d, got %d", want.Status, actual.Status)
	}
	if want.Detail != "" && (actual.Detail == nil || *actual.Detail != want.Detail) {
		return actual, fmt.Errorf("problem detail: want %q, got %v", want.Detail, describe(actual.Detail))
	}
	if want.Instance != "" && (actual.Instance == nil || *actual.Instance != want.Instance) {
		return actual, fmt.Errorf("problem instance: want %q, got %v", want.Instance, describe(actual.Instance))
	}
	if want.Data != nil && !maps.EqualFunc(want.Data, actual.Data, equalValue) {
		return actual, fmt.Errorf("problem data: want %v, got %v", want.Data, actual.Data)
	}
	return actual, nil
}

// describe renders an optional string member for a failure message.
func describe(value *string) string {
	if value == nil {
		return "<absent>"
	}
	return fmt.Sprintf("%q", *value)
}

// equalValue compares two `data` members.
//
// JSON decoding turns every number into a float64 and every nested object into
// a map[string]any, so reflect.DeepEqual is the comparison that actually holds
// across a round trip; == would reject an equal []any outright.
func equalValue(want any, actual any) bool {
	return reflect.DeepEqual(want, actual)
}

// AssertProblem fails t unless err carries the expected problem envelope, and
// returns the envelope it found.
//
// Only the fields set on want are compared, so a test asserts the `data`
// extension it cares about without restating the whole envelope.
func AssertProblem(t TestingT, err error, want ProblemOptions) problem.Problem {
	t.Helper()
	actual, checkErr := CheckProblem(err, want)
	if checkErr != nil {
		t.Errorf("%v", checkErr)
	}
	return actual
}

// CheckOutcome reports whether outcome is the expected one.
func CheckOutcome(actual apiengine.Outcome, want apiengine.Outcome) error {
	if actual != want {
		return fmt.Errorf("outcome: want %s, got %s", want, actual)
	}
	return nil
}

// AssertOutcome fails t unless the response carries the expected 3-case
// classification.
func AssertOutcome(t TestingT, actual apiengine.Outcome, want apiengine.Outcome) {
	t.Helper()
	if err := CheckOutcome(actual, want); err != nil {
		t.Errorf("%v", err)
	}
}

// CheckCount reports whether a fake backend received the expected number of
// requests.
//
// It is how the retry-once profile is asserted: a call that survived one
// transport failure leaves exactly two.
func CheckCount(backend *FakeBackend, want int) error {
	if actual := backend.Count(); actual != want {
		return fmt.Errorf("request count: want %d, got %d", want, actual)
	}
	return nil
}

// AssertCount fails t unless the backend received exactly want requests.
func AssertCount(t TestingT, backend *FakeBackend, want int) {
	t.Helper()
	if err := CheckCount(backend, want); err != nil {
		t.Errorf("%v", err)
	}
}
