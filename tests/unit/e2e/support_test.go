package e2e_test

import (
	"context"
	"errors"
	"io"
	"strings"
	"testing"

	"github.com/AtomiCloud/diene.go-e2e/lib/e2e"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

// samplePortal is the error portal every unit test raises problems from. It is
// the published errors-problems sibling's own local portal, so the type URIs
// asserted here are the ones the single-source builder produces.
func samplePortal() problem.ErrorPortal {
	return problem.LocalErrorPortal()
}

// brokenPortal is a portal the single-source type-URI builder must refuse,
// which is how the uncatalogued fallback path is reached.
func brokenPortal() problem.ErrorPortal {
	portal := samplePortal()
	portal.Host = ""
	return portal
}

// requireProblems builds the harness problem factory or fails the test.
func requireProblems(t *testing.T, portal problem.ErrorPortal) *e2e.Problems {
	t.Helper()
	problems, err := e2e.NewProblems(portal)
	if err != nil {
		t.Fatalf("NewProblems() error = %v", err)
	}
	return problems
}

// problemID extracts the trailing id segment of a problem type URI.
func problemID(t *testing.T, err error) string {
	t.Helper()
	if err == nil {
		t.Fatal("expected a problem-typed error, got nil")
	}
	var typed *problem.Error
	if !errors.As(err, &typed) {
		t.Fatalf("expected a problem-typed error, got %v", err)
	}
	index := strings.LastIndex(typed.Problem.Type, "/")
	if index < 0 {
		return typed.Problem.Type
	}
	return typed.Problem.Type[index+1:]
}

// problemData extracts the `data` extension of a problem-typed error.
func problemData(t *testing.T, err error) map[string]any {
	t.Helper()
	var typed *problem.Error
	if !errors.As(err, &typed) {
		t.Fatalf("expected a problem-typed error, got %v", err)
	}
	return typed.Problem.Data
}

// echo is an entrypoint that writes its arguments and environment back out and
// exits with the code the `EXIT` variable names.
func echo(_ context.Context, invocation e2e.Invocation, stdout io.Writer, stderr io.Writer) (int, error) {
	if _, err := io.WriteString(stdout, "args="+strings.Join(invocation.Args, ",")); err != nil {
		return 0, err
	}
	if value, found := invocation.Env["MARKER"]; found {
		if _, err := io.WriteString(stdout, " marker="+value); err != nil {
			return 0, err
		}
	}
	if _, err := io.WriteString(stdout, " dir="+invocation.WorkingDirectory); err != nil {
		return 0, err
	}
	if invocation.Env["EXIT"] == "3" {
		if _, err := io.WriteString(stderr, "failed"); err != nil {
			return 0, err
		}
		return 3, nil
	}
	return 0, nil
}

// errBoom is the arbitrary underlying failure seams are made to return.
var errBoom = errors.New("boom")

// failingEntrypoint never reaches a verdict.
func failingEntrypoint(context.Context, e2e.Invocation, io.Writer, io.Writer) (int, error) {
	return 0, errBoom
}
