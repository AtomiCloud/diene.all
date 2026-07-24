package faults_test

import (
	"errors"
	"testing"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
	probtest "github.com/AtomiCloud/diene.go-errors-problems/testhelper"
	"github.com/AtomiCloud/diene.go-interfaces/testhelper/internal/faults"
)

const typePrefix = "https://docs.diene.atomicloud.com/docs/diene/go/interfaces/testhelper/v1/"

// TestIntrinsicFaults proves each intrinsic fault mints the canonical type URI
// from the fixed portal (never an empty string from a silently discarded
// builder error), carries the right id/status, and echoes its occurrence in
// Detail and Data.
func TestIntrinsicFaults(t *testing.T) {
	cases := []struct {
		name   string
		err    error
		id     string
		status int
		detail string
	}{
		{"path-not-found", faults.PathNotFound("/missing"), "path-not-found", 404, "/missing"},
		{"directory-not-empty", faults.DirectoryNotEmpty("/dir"), "directory-not-empty", 409, "/dir"},
		{"terminal-result-not-scripted", faults.TerminalNotScripted("tool"), "terminal-result-not-scripted", 500, "tool"},
	}
	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			envelope := probtest.AssertError(
				t, testCase.err,
				probtest.ExpectType(typePrefix+testCase.id),
				probtest.ExpectID(testCase.id),
				probtest.ExpectStatus(testCase.status),
				probtest.ExpectDetail(testCase.detail),
				probtest.ExpectData(map[string]any{"id": testCase.id}),
			)
			if envelope.Type == "" {
				t.Fatal("type URI must not be empty: the fixed portal must never fail the builder")
			}
		})
	}
}

// TestNormalizeNilStaysNil proves a nil error is left nil.
func TestNormalizeNilStaysNil(t *testing.T) {
	if err := faults.Normalize(nil); err != nil {
		t.Fatalf("expected nil, got %v", err)
	}
}

// TestNormalizeWrapsPlainError proves a plain error is wrapped so it becomes
// *problem.Error-recoverable while still reaching its cause via errors.Is.
func TestNormalizeWrapsPlainError(t *testing.T) {
	cause := errors.New("boom")
	normalized := faults.Normalize(cause)
	var problemErr *problem.Error
	if !errors.As(normalized, &problemErr) || problemErr == nil {
		t.Fatalf("expected a *problem.Error, got %#v", normalized)
	}
	if !errors.Is(normalized, cause) {
		t.Fatal("errors.Is must still reach the original cause")
	}
}

// TestNormalizePreservesProblem proves an already problem-typed error is
// returned unchanged.
func TestNormalizePreservesProblem(t *testing.T) {
	original := faults.PathNotFound("/keep")
	if normalized := faults.Normalize(original); !errors.Is(normalized, original) {
		t.Fatalf("expected the original problem error preserved, got %#v", normalized)
	}
	probtest.AssertError(t, faults.Normalize(original), probtest.ExpectID("path-not-found"))
}
