package authengine_test

import (
	"errors"
	"testing"

	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
	"github.com/AtomiCloud/diene.go-auth-engine/testhelper"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

// errFake is the failure suites inject through the fakes' scripted error queues.
var errFake = errors.New("scripted failure")

// newProblems builds the engine's problem factory over a valid sample portal.
func newProblems(t *testing.T) *authengine.Problems {
	t.Helper()

	problems, err := authengine.NewProblems(testhelper.SampleErrorPortal())
	if err != nil {
		t.Fatalf("expected a problem factory, got %v", err)
	}
	return problems
}

// newIDP builds a fake identity provider signing real tokens.
func newIDP(t *testing.T) *testhelper.FakeIDP {
	t.Helper()

	idp, err := testhelper.NewFakeIDP(testhelper.FakeIDPOptions{})
	if err != nil {
		t.Fatalf("expected a fake IdP, got %v", err)
	}
	return idp
}

// requireProblem asserts err carries the auth problem id and returns the envelope.
func requireProblem(t *testing.T, err error, id string) problem.Problem {
	t.Helper()

	envelope, failure := testhelper.CheckAuthProblem(err, id)
	if failure != nil {
		t.Fatalf("%v", failure)
	}
	return envelope
}

// requireNoError fails the test when err is non-nil.
func requireNoError(t *testing.T, err error) {
	t.Helper()

	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
}
