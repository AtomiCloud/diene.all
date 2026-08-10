package examplecov_test

import (
	"bytes"
	"strings"
	"testing"

	"github.com/AtomiCloud/diene.go-config/internal/examplecov"
)

func TestAnalyzeReportsUncovered(t *testing.T) {
	t.Parallel()
	analysis, err := examplecov.Analyze("testdata/sample")
	if err != nil {
		t.Fatalf("analyze: %v", err)
	}
	uncovered := map[string]bool{}
	for _, requirement := range analysis.Uncovered() {
		uncovered[requirement.Name] = true
	}
	if !uncovered["Global"] || !uncovered["Reader_Read"] {
		t.Fatalf("expected Global and Reader_Read uncovered, got %v", analysis.Uncovered())
	}
	for _, covered := range []string{"Answer", "Meters", "Widget", "Widget_Render", "Widget_name", "Reader", "Build"} {
		if uncovered[covered] {
			t.Fatalf("%q is covered and must not be reported", covered)
		}
	}
}

func TestSatisfiedByMatchingModes(t *testing.T) {
	t.Parallel()
	examples := map[string]bool{"Foo": true, "Bar_baz": true}
	if !(examplecov.Requirement{Name: "Foo"}).SatisfiedBy(examples) {
		t.Fatal("an exact-name example satisfies a flexible requirement")
	}
	if !(examplecov.Requirement{Name: "Bar"}).SatisfiedBy(examples) {
		t.Fatal("a lowercase-suffix variant satisfies a flexible requirement")
	}
	if (examplecov.Requirement{Name: "Bar", Exact: true}).SatisfiedBy(examples) {
		t.Fatal("an exact requirement is not satisfied by a suffix variant")
	}
	if (examplecov.Requirement{Name: "Absent"}).SatisfiedBy(examples) {
		t.Fatal("an absent flexible requirement is unsatisfied")
	}
}

func TestLowerInitial(t *testing.T) {
	t.Parallel()
	if examplecov.LowerInitial("Landscape") != "landscape" {
		t.Fatal("LowerInitial must lowercase the first rune")
	}
	if examplecov.LowerInitial("") != "" {
		t.Fatal("LowerInitial of empty is empty")
	}
}

func TestRunExitCodes(t *testing.T) {
	t.Parallel()
	var out, errOut bytes.Buffer
	if code := examplecov.Run(nil, &out, &errOut); code != 2 {
		t.Fatalf("no arguments must be a usage fault (2), got %d", code)
	}

	out.Reset()
	errOut.Reset()
	if code := examplecov.Run([]string{"testdata/sample"}, &out, &errOut); code != 1 {
		t.Fatalf("uncovered symbols must exit 1, got %d", code)
	}
	if !strings.Contains(errOut.String(), "Reader_Read") {
		t.Fatalf("diagnostics must name the missing example: %s", errOut.String())
	}

	out.Reset()
	errOut.Reset()
	if code := examplecov.Run([]string{"testdata/empty"}, &out, &errOut); code != 0 {
		t.Fatalf("a fully-covered package must exit 0, got %d (%s)", code, errOut.String())
	}

	out.Reset()
	errOut.Reset()
	if code := examplecov.Run([]string{"testdata/does-not-exist"}, &out, &errOut); code != 2 {
		t.Fatalf("a parse fault must exit 2, got %d", code)
	}
}
