package problem_test

import (
	"errors"
	"fmt"
	"testing"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

func TestErrorWithoutWrap(t *testing.T) {
	t.Parallel()
	envelope := problem.Problem{Type: "t", Title: "T", Status: 404}
	err := problem.NewError(envelope)
	if err.Error() != envelope.String() {
		t.Fatalf("Error() = %q, want %q", err.Error(), envelope.String())
	}
	if err.Unwrap() != nil {
		t.Fatalf("expected nil unwrap, got %v", err.Unwrap())
	}
}

func TestErrorWrapsCause(t *testing.T) {
	t.Parallel()
	cause := errors.New("boom")
	envelope := problem.Problem{Type: "t", Title: "T", Status: 500}
	err := problem.WrapError(envelope, cause)
	if !errors.Is(err.Unwrap(), cause) {
		t.Fatalf("expected wrapped cause, got %v", err.Unwrap())
	}
	if !errors.Is(err, cause) {
		t.Fatal("errors.Is should find the wrapped cause")
	}
	want := envelope.String() + ": boom"
	if err.Error() != want {
		t.Fatalf("Error() = %q, want %q", err.Error(), want)
	}
}

func TestErrorRecoverableViaErrorsAs(t *testing.T) {
	t.Parallel()
	envelope := problem.Problem{Type: "t", Title: "T", Status: 409}
	wrapped := fmt.Errorf("context: %w", problem.NewError(envelope))
	var problemErr *problem.Error
	if !errors.As(wrapped, &problemErr) {
		t.Fatal("errors.As should recover the Error")
	}
	if !problemErr.Problem.Equal(envelope) {
		t.Fatalf("recovered problem mismatch: %+v", problemErr.Problem)
	}
}
