package testhelper

import (
	"errors"
	"strings"

	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
	"github.com/AtomiCloud/diene.go-auth-engine/lib/onboard"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

// TestingT is the minimal subset of *testing.T the assertion helpers use.
//
// Depending on the interface rather than the concrete type keeps the helpers
// framework-free and — more importantly — lets them be black-box tested with a
// recording double, which is how the meta tier proves an assertion fails on
// known-bad input instead of merely passing on known-good.
type TestingT interface {
	// Helper marks the caller as a test helper.
	Helper()
	// Fatalf reports a fatal failure.
	Fatalf(format string, args ...any)
}

// AssertAuthProblem fails t unless err carries an auth-engine problem with the
// expected id.
//
// Matching on the ID rather than the full type URI is deliberate: the URI embeds the
// consumer's own landscape, platform, service, and module, so a test that spelled it
// out would break the moment it ran in a different landscape.
func AssertAuthProblem(t TestingT, err error, id string) problem.Problem {
	t.Helper()
	envelope, failure := CheckAuthProblem(err, id)
	if failure != nil {
		t.Fatalf("%s", failure.Error())
	}
	return envelope
}

// CheckAuthProblem recovers an auth-engine problem from a (T, error) result and
// verifies its id, returning a descriptive error rather than failing a test.
//
// It is the half a consumer composes into its own assertions, and the half the meta
// tier drives directly.
func CheckAuthProblem(err error, id string) (problem.Problem, error) {
	if err == nil {
		return problem.Problem{}, errors.New("expected an auth problem " + id + ", got no error")
	}
	var carried *problem.Error
	if !errors.As(err, &carried) {
		return problem.Problem{}, errors.New(
			"expected an auth problem " + id + ", got a plain error: " + err.Error(),
		)
	}
	if actual := ProblemID(carried.Problem); actual != id {
		return problem.Problem{}, errors.New(
			"expected auth problem " + id + ", got " + actual,
		)
	}
	return carried.Problem, nil
}

// AssertNoAuthProblem fails t when err is non-nil, rendering the carried problem so
// the failure message names the auth decision that went wrong rather than just
// "unexpected error".
func AssertNoAuthProblem(t TestingT, err error) {
	t.Helper()
	if err == nil {
		return
	}
	var carried *problem.Error
	if errors.As(err, &carried) {
		t.Fatalf("expected no auth problem, got %s: %s", ProblemID(carried.Problem), carried.Problem.String())
		return
	}
	t.Fatalf("expected no auth problem, got %s", err.Error())
}

// AssertOwnershipDenied fails t unless err is the ownership-denied problem, which is
// the single most repeated assertion in a consumer's guard tests.
func AssertOwnershipDenied(t TestingT, err error) problem.Problem {
	t.Helper()
	return AssertAuthProblem(t, err, authengine.ProblemOwnershipDenied)
}

// AssertPhase fails t unless the backend's onboarding state reached want.
func AssertPhase(t TestingT, states map[string]onboard.State, backend string, want onboard.Phase) {
	t.Helper()
	if failure := CheckPhase(states, backend, want); failure != nil {
		t.Fatalf("%s", failure.Error())
	}
}

// CheckPhase verifies one backend's onboarding phase, returning a descriptive error
// rather than failing a test. A backend absent from the round is reported as such
// rather than compared against the zero phase, because "never ran" and "ran and
// failed" are different bugs.
func CheckPhase(states map[string]onboard.State, backend string, want onboard.Phase) error {
	state, found := states[backend]
	if !found {
		return errors.New("onboarding round has no state for backend " + backend)
	}
	if state.Phase != want {
		message := "expected backend " + backend + " in phase " + string(want) +
			", got " + string(state.Phase)
		if state.Err != nil {
			message += " (" + state.Err.Error() + ")"
		}
		return errors.New(message)
	}
	return nil
}

// ProblemID returns the trailing id segment of a problem type URI, so a caller can
// match a problem without spelling out the consumer-specific URI.
func ProblemID(envelope problem.Problem) string {
	index := strings.LastIndex(envelope.Type, "/")
	if index < 0 {
		return envelope.Type
	}
	return envelope.Type[index+1:]
}
