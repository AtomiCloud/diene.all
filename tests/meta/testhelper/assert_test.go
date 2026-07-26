package testhelper_test

import (
	"strings"
	"testing"

	"github.com/AtomiCloud/diene.go-e2e/lib/e2e"
	"github.com/AtomiCloud/diene.go-e2e/testhelper"
)

// passingJourney is the two-step journey the report assertions are proven
// against.
func passingJourney() e2e.Journey {
	return e2e.Journey{
		Name: "seed-then-verify",
		Steps: []e2e.Step{
			{Name: "seed", Invocation: e2e.Invocation{}, Expect: e2e.Expectation{ExitCode: 0, StdoutContains: []string{"seeded"}}},
			{Name: "verify", Invocation: e2e.Invocation{}, Expect: e2e.Expectation{ExitCode: 0}},
		},
	}
}

// passingReport is a report that satisfies [passingJourney].
func passingReport() e2e.Report {
	return e2e.Report{
		Driver:  "scripted",
		Journey: "seed-then-verify",
		Steps: []e2e.StepReport{
			{Name: "seed", Result: e2e.Result{ExitCode: 0, Stdout: "seeded"}},
			{Name: "verify", Result: e2e.Result{ExitCode: 0}},
		},
	}
}

func TestAssertResultPassesAndFails(t *testing.T) {
	t.Parallel()

	want := e2e.Expectation{ExitCode: 0, StdoutContains: []string{"ready"}}

	good := &recorder{}
	testhelper.AssertResult(good, e2e.Result{ExitCode: 0, Stdout: "ready"}, want)
	expectPass(t, good)

	bad := &recorder{}
	testhelper.AssertResult(bad, e2e.Result{ExitCode: 1, Stdout: "ready"}, want)
	expectFail(t, bad, "exit code 1 is not 0")

	if err := testhelper.CheckResult(e2e.Result{ExitCode: 0, Stdout: "ready"}, want); err != nil {
		t.Fatalf("CheckResult() error = %v, want nil", err)
	}
	if err := testhelper.CheckResult(e2e.Result{}, want); err == nil {
		t.Fatal("CheckResult() error = nil, want a mismatch")
	}
}

func TestAssertStepPassesAndFails(t *testing.T) {
	t.Parallel()

	step := passingJourney().Steps[0]

	good := &recorder{}
	testhelper.AssertStep(good, step, e2e.Result{Stdout: "seeded"})
	expectPass(t, good)

	bad := &recorder{}
	testhelper.AssertStep(bad, step, e2e.Result{Stdout: "nothing"})
	expectFail(t, bad, `stdout is missing "seeded"`)

	if err := testhelper.CheckStep(step, e2e.Result{Stdout: "seeded"}); err != nil {
		t.Fatalf("CheckStep() error = %v, want nil", err)
	}
	if err := testhelper.CheckStep(step, e2e.Result{}); err == nil {
		t.Fatal("CheckStep() error = nil, want a mismatch")
	}
}

func TestAssertReportPassesAndFailsOnEveryDivergence(t *testing.T) {
	t.Parallel()

	journey := passingJourney()

	good := &recorder{}
	testhelper.AssertReport(good, passingReport(), journey)
	expectPass(t, good)

	cases := []struct {
		name     string
		report   e2e.Report
		fragment string
	}{
		{
			name:     "wrong journey",
			report:   e2e.Report{Driver: "scripted", Journey: "other", Steps: passingReport().Steps},
			fragment: "report is for journey",
		},
		{
			name:     "missing step",
			report:   e2e.Report{Driver: "scripted", Journey: journey.Name, Steps: passingReport().Steps[:1]},
			fragment: "report covers 1 steps, want 2",
		},
		{
			name: "renamed step",
			report: e2e.Report{Driver: "scripted", Journey: journey.Name, Steps: []e2e.StepReport{
				{Name: "seed", Result: e2e.Result{Stdout: "seeded"}},
				{Name: "renamed", Result: e2e.Result{}},
			}},
			fragment: `step 1 is "renamed"`,
		},
		{
			name: "failing step",
			report: e2e.Report{Driver: "scripted", Journey: journey.Name, Steps: []e2e.StepReport{
				{Name: "seed", Result: e2e.Result{ExitCode: 7, Stdout: "seeded"}},
				{Name: "verify", Result: e2e.Result{}},
			}},
			fragment: "exit code 7 is not 0",
		},
	}
	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			t.Parallel()
			observed := &recorder{}
			testhelper.AssertReport(observed, testCase.report, journey)
			expectFail(t, observed, testCase.fragment)
			if err := testhelper.CheckReport(testCase.report, journey); err == nil {
				t.Fatal("CheckReport() error = nil, want a divergence")
			}
		})
	}
}

func TestAssertHarnessProblemPassesAndFails(t *testing.T) {
	t.Parallel()

	problems := requireProblems(t)
	raised := problems.Raise(e2e.ProblemJourneyEmpty, "nothing to run", nil)

	good := &recorder{}
	envelope := testhelper.AssertHarnessProblem(good, raised, e2e.ProblemJourneyEmpty)
	expectPass(t, good)
	if !strings.HasSuffix(envelope.Type, "/"+e2e.ProblemJourneyEmpty) {
		t.Fatalf("envelope type = %q, want the journey-empty problem", envelope.Type)
	}

	cases := []struct {
		name     string
		err      error
		id       string
		fragment string
	}{
		{"no error", nil, e2e.ProblemJourneyEmpty, "got no error"},
		{"plain error", errBoom, e2e.ProblemJourneyEmpty, "got a plain error"},
		{"wrong problem", raised, e2e.ProblemStepFailed, "got type"},
	}
	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			t.Parallel()
			observed := &recorder{}
			testhelper.AssertHarnessProblem(observed, testCase.err, testCase.id)
			expectFail(t, observed, testCase.fragment)
			if _, err := testhelper.CheckHarnessProblem(testCase.err, testCase.id); err == nil {
				t.Fatal("CheckHarnessProblem() error = nil, want a mismatch")
			}
		})
	}
}

func TestAssertNoHarnessProblemPassesAndFails(t *testing.T) {
	t.Parallel()

	good := &recorder{}
	testhelper.AssertNoHarnessProblem(good, nil)
	expectPass(t, good)

	bad := &recorder{}
	testhelper.AssertNoHarnessProblem(bad, errBoom)
	expectFail(t, bad, "unexpected harness failure")
}

func TestRequireReportPassesAndFails(t *testing.T) {
	t.Parallel()

	good := &recorder{}
	got := testhelper.RequireReport(good, passingReport(), nil)
	expectPass(t, good)
	if got.Journey != "seed-then-verify" {
		t.Fatalf("RequireReport() = %+v, want the report returned", got)
	}

	bad := &recorder{}
	testhelper.RequireReport(bad, e2e.Report{}, errBoom)
	expectFail(t, bad, "journey did not complete")
}

func TestSampleProblemsIsUsableWithoutAPortal(t *testing.T) {
	t.Parallel()

	problems, err := testhelper.SampleProblems()
	if err != nil {
		t.Fatalf("SampleProblems() error = %v", err)
	}
	if got := len(problems.Registry().Entries()); got != len(e2e.ProblemTypes()) {
		t.Fatalf("registry entries = %d, want %d", got, len(e2e.ProblemTypes()))
	}
	catalog, err := problems.Catalog()
	if err != nil {
		t.Fatalf("Catalog() error = %v", err)
	}
	if len(catalog.Entries()) == 0 {
		t.Fatal("catalog is empty, want the harness problems catalogued")
	}
}
