package e2e_test

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/AtomiCloud/diene.go-e2e/lib/e2e"
	"github.com/AtomiCloud/diene.go-e2e/testhelper"
)

// journeySteps is the two-step narrative every journey test runs.
func journeySteps() e2e.Journey {
	return e2e.Journey{
		Name: "seed-then-verify",
		Steps: []e2e.Step{
			{
				Name:       "seed",
				Invocation: e2e.Invocation{Args: []string{"seed"}},
				Expect:     e2e.Expectation{ExitCode: 0, StdoutContains: []string{"args=seed"}},
			},
			{
				Name:       "verify",
				Invocation: e2e.Invocation{Args: []string{"verify"}},
				Expect:     e2e.Expectation{ExitCode: 0, StdoutContains: []string{"args=verify"}},
			},
		},
	}
}

func requireEchoDriver(t *testing.T, problems *e2e.Problems, label string) *e2e.InProcessDriver {
	t.Helper()
	driver, err := e2e.NewInProcessDriver(e2e.InProcessOptions{
		Label:      label,
		Entrypoint: echo,
		Problems:   problems,
	})
	if err != nil {
		t.Fatalf("NewInProcessDriver() error = %v", err)
	}
	return driver
}

func TestRunJourneyNeedsAProblemFactory(t *testing.T) {
	t.Parallel()

	_, err := e2e.RunJourney(context.Background(), nil, journeySteps(), nil)
	if err == nil || err.Error() != "e2e: problems is required" {
		t.Fatalf("RunJourney() error = %v, want the unconfigured message", err)
	}
}

func TestRunJourneyNeedsADriver(t *testing.T) {
	t.Parallel()

	problems := requireProblems(t, samplePortal())
	_, err := e2e.RunJourney(context.Background(), nil, journeySteps(), problems)
	if got := problemID(t, err); got != e2e.ProblemDriverUnconfigured {
		t.Fatalf("problem id = %q, want %q", got, e2e.ProblemDriverUnconfigured)
	}
}

func TestRunJourneyRefusesAnEmptyJourney(t *testing.T) {
	t.Parallel()

	problems := requireProblems(t, samplePortal())
	driver := requireEchoDriver(t, problems, "echo")
	_, err := e2e.RunJourney(context.Background(), driver, e2e.Journey{Name: "vacuous"}, problems)
	if got := problemID(t, err); got != e2e.ProblemJourneyEmpty {
		t.Fatalf("problem id = %q, want %q", got, e2e.ProblemJourneyEmpty)
	}
	if problemData(t, err)["journey"] != "vacuous" {
		t.Fatalf("problem data = %v, want the journey named", problemData(t, err))
	}
}

func TestRunJourneyReportsEveryStepInOrder(t *testing.T) {
	t.Parallel()

	problems := requireProblems(t, samplePortal())
	driver := requireEchoDriver(t, problems, "echo")
	journey := journeySteps()
	report, err := e2e.RunJourney(context.Background(), driver, journey, problems)
	if err != nil {
		t.Fatalf("RunJourney() error = %v", err)
	}
	if report.Driver != "echo" || report.Journey != journey.Name {
		t.Fatalf("report = %+v, want the driver and journey named", report)
	}
	if len(report.Steps) != 2 {
		t.Fatalf("report covers %d steps, want 2", len(report.Steps))
	}
	if report.Steps[0].Name != "seed" || report.Steps[1].Name != "verify" {
		t.Fatalf("report steps = %+v, want seed then verify", report.Steps)
	}
}

func TestRunJourneyStopsAtTheFirstFailingStep(t *testing.T) {
	t.Parallel()

	problems := requireProblems(t, samplePortal())
	driver := requireEchoDriver(t, problems, "echo")
	journey := e2e.Journey{
		Name: "fails-early",
		Steps: []e2e.Step{
			{Name: "first", Invocation: e2e.Invocation{Env: map[string]string{"EXIT": "3"}}, Expect: e2e.Expectation{ExitCode: 0}},
			{Name: "second", Invocation: e2e.Invocation{}, Expect: e2e.Expectation{ExitCode: 0}},
		},
	}
	report, err := e2e.RunJourney(context.Background(), driver, journey, problems)
	if got := problemID(t, err); got != e2e.ProblemStepFailed {
		t.Fatalf("problem id = %q, want %q", got, e2e.ProblemStepFailed)
	}
	data := problemData(t, err)
	if data["step"] != "first" || data["index"] != 0 || data["exitCode"] != 3 {
		t.Fatalf("problem data = %v, want the failing step described", data)
	}
	if len(report.Steps) != 1 {
		t.Fatalf("report covers %d steps, want only the failing one", len(report.Steps))
	}
	var mismatch *e2e.StepMismatchError
	if !errors.As(err, &mismatch) {
		t.Fatal("errors.As(err, &StepMismatchError) = false, want the typed mismatch to survive")
	}
	if mismatch.Step != "first" {
		t.Fatalf("mismatch step = %q, want first", mismatch.Step)
	}
	if !strings.Contains(mismatch.Error(), "exit code 3 is not 0") {
		t.Fatalf("mismatch = %q, want the exit-code reason", mismatch.Error())
	}
}

func TestRunJourneySurfacesADriverFailureUnchanged(t *testing.T) {
	t.Parallel()

	problems := requireProblems(t, samplePortal())
	driver := testhelper.NewScriptedDriver("scripted", testhelper.ScriptedStep{Err: errBoom})
	_, err := e2e.RunJourney(context.Background(), driver, journeySteps(), problems)
	if !errors.Is(err, errBoom) {
		t.Fatalf("RunJourney() error = %v, want the driver failure surfaced", err)
	}
}

func TestCheckStepCoversEveryExpectation(t *testing.T) {
	t.Parallel()

	step := func(expect e2e.Expectation) e2e.Step {
		return e2e.Step{Name: "case", Invocation: e2e.Invocation{}, Expect: expect}
	}
	result := e2e.Result{ExitCode: 0, Stdout: "hello world", Stderr: "warn: slow"}

	if err := e2e.CheckStep(step(e2e.Expectation{
		StdoutContains: []string{"hello", "world"},
		StderrContains: []string{"warn"},
		StdoutExcludes: []string{"panic"},
	}), result); err != nil {
		t.Fatalf("CheckStep() error = %v, want nil for a satisfied expectation", err)
	}

	cases := []struct {
		name   string
		expect e2e.Expectation
		reason string
	}{
		{"exit code", e2e.Expectation{ExitCode: 1}, "exit code 0 is not 1"},
		{"stdout missing", e2e.Expectation{StdoutContains: []string{"absent"}}, `stdout is missing "absent"`},
		{"stderr missing", e2e.Expectation{StderrContains: []string{"absent"}}, `stderr is missing "absent"`},
		{"stdout excluded", e2e.Expectation{StdoutExcludes: []string{"hello"}}, `stdout unexpectedly contains "hello"`},
	}
	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			t.Parallel()
			err := e2e.CheckStep(step(testCase.expect), result)
			if err == nil {
				t.Fatal("CheckStep() error = nil, want a mismatch")
			}
			if !strings.Contains(err.Error(), testCase.reason) {
				t.Fatalf("CheckStep() error = %q, want it to mention %q", err.Error(), testCase.reason)
			}
		})
	}
}

func TestCompareReportsNeedsAProblemFactory(t *testing.T) {
	t.Parallel()

	err := e2e.CompareReports(e2e.Report{}, e2e.Report{}, nil)
	if err == nil || err.Error() != "e2e: problems is required" {
		t.Fatalf("CompareReports() error = %v, want the unconfigured message", err)
	}
}

func TestCompareReportsAcceptsAgreeingRuns(t *testing.T) {
	t.Parallel()

	problems := requireProblems(t, samplePortal())
	left := e2e.Report{Driver: "compiled", Journey: "j", Steps: []e2e.StepReport{{Name: "one", Result: e2e.Result{ExitCode: 2}}}}
	right := e2e.Report{Driver: "in-process", Journey: "j", Steps: []e2e.StepReport{{
		Name:   "one",
		Result: e2e.Result{ExitCode: 2, Stdout: "different buffering entirely"},
	}}}
	if err := e2e.CompareReports(left, right, problems); err != nil {
		t.Fatalf("CompareReports() error = %v, want streams to be allowed to differ", err)
	}
}

func TestCompareReportsRejectsEveryDivergence(t *testing.T) {
	t.Parallel()

	problems := requireProblems(t, samplePortal())
	base := e2e.Report{Driver: "compiled", Journey: "j", Steps: []e2e.StepReport{
		{Name: "one", Result: e2e.Result{ExitCode: 0}},
		{Name: "two", Result: e2e.Result{ExitCode: 0}},
	}}
	cases := []struct {
		name  string
		right e2e.Report
	}{
		{"different journey", e2e.Report{Driver: "in-process", Journey: "other", Steps: base.Steps}},
		{"different length", e2e.Report{Driver: "in-process", Journey: "j", Steps: base.Steps[:1]}},
		{"different step", e2e.Report{Driver: "in-process", Journey: "j", Steps: []e2e.StepReport{
			{Name: "one", Result: e2e.Result{ExitCode: 0}},
			{Name: "different", Result: e2e.Result{ExitCode: 0}},
		}}},
		{"different exit code", e2e.Report{Driver: "in-process", Journey: "j", Steps: []e2e.StepReport{
			{Name: "one", Result: e2e.Result{ExitCode: 0}},
			{Name: "two", Result: e2e.Result{ExitCode: 9}},
		}}},
	}
	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			t.Parallel()
			err := e2e.CompareReports(base, testCase.right, problems)
			if got := problemID(t, err); got != e2e.ProblemParityMismatch {
				t.Fatalf("problem id = %q, want %q", got, e2e.ProblemParityMismatch)
			}
		})
	}
}

func TestRunParityProvesTwoDriversAgree(t *testing.T) {
	t.Parallel()

	problems := requireProblems(t, samplePortal())
	compiled := requireEchoDriver(t, problems, "compiled")
	inProcess := requireEchoDriver(t, problems, "in-process")
	first, second, err := e2e.RunParity(context.Background(), compiled, inProcess, journeySteps(), problems)
	if err != nil {
		t.Fatalf("RunParity() error = %v", err)
	}
	if first.Driver != "compiled" || second.Driver != "in-process" {
		t.Fatalf("reports = %q/%q, want one per driver", first.Driver, second.Driver)
	}
}

func TestRunParityStopsWhenTheFirstDriverFails(t *testing.T) {
	t.Parallel()

	problems := requireProblems(t, samplePortal())
	broken := testhelper.NewScriptedDriver("broken", testhelper.ScriptedStep{Err: errBoom})
	inProcess := requireEchoDriver(t, problems, "in-process")
	_, second, err := e2e.RunParity(context.Background(), broken, inProcess, journeySteps(), problems)
	if !errors.Is(err, errBoom) {
		t.Fatalf("RunParity() error = %v, want the first driver's failure", err)
	}
	if len(second.Steps) != 0 {
		t.Fatalf("second report = %+v, want an unattempted run", second)
	}
}

func TestRunParityStopsWhenTheSecondDriverFails(t *testing.T) {
	t.Parallel()

	problems := requireProblems(t, samplePortal())
	compiled := requireEchoDriver(t, problems, "compiled")
	broken := testhelper.NewScriptedDriver("broken", testhelper.ScriptedStep{Err: errBoom})
	_, _, err := e2e.RunParity(context.Background(), compiled, broken, journeySteps(), problems)
	if !errors.Is(err, errBoom) {
		t.Fatalf("RunParity() error = %v, want the second driver's failure", err)
	}
}
