package testhelper_test

import (
	"context"
	"fmt"

	"github.com/AtomiCloud/diene.go-e2e/lib/e2e"
	"github.com/AtomiCloud/diene.go-e2e/testhelper"
)

// exampleT satisfies [testhelper.TestingT] outside a test binary, so the
// examples can show what a failing assertion says.
type exampleT struct{}

// Helper is a no-op outside a test binary.
func (exampleT) Helper() {}

// Fatalf prints instead of aborting.
func (exampleT) Fatalf(format string, args ...any) {
	fmt.Printf(format+"\n", args...)
}

// exampleProblems builds the harness problem factory on the shared sample
// portal.
func exampleProblems() *e2e.Problems {
	problems, err := testhelper.SampleProblems()
	if err != nil {
		panic(err)
	}
	return problems
}

func ExampleSampleProblems() {
	problems := exampleProblems()
	fmt.Println(len(problems.Registry().Entries()))
	// Output: 10
}

func ExampleNewScriptedDriver() {
	driver := testhelper.NewScriptedDriver(
		"scripted",
		testhelper.ScriptedStep{Result: e2e.Result{ExitCode: 0, Stdout: "seeded"}},
	)
	result, err := driver.Run(context.Background(), e2e.Invocation{Args: []string{"seed"}})
	if err != nil {
		panic(err)
	}
	fmt.Println(driver.Name(), result.Stdout, driver.Remaining())
	fmt.Println(driver.Calls()[0].Args)
	// Output:
	// scripted seeded 0
	// [seed]
}

func ExampleNewScriptedDriver_exhausted() {
	// A script that runs out REFUSES rather than inventing a zero result, because
	// a silent zero would let a journey pass on a step nobody anticipated.
	driver := testhelper.NewScriptedDriver("scripted")
	_, err := driver.Run(context.Background(), e2e.Invocation{})
	fmt.Println(err)
	// Output: testhelper: the scripted driver has no answer left
}

func ExampleNewEchoDriver() {
	driver, err := testhelper.NewEchoDriver(exampleProblems())
	if err != nil {
		panic(err)
	}
	result, err := driver.Run(context.Background(), e2e.Invocation{
		Args: []string{"seed"},
		Env:  map[string]string{"MARKER": "one"},
	})
	if err != nil {
		panic(err)
	}
	fmt.Print(result.Stdout)
	// Output:
	// args: seed
	// env: MARKER=one
}

func ExampleAssertResult() {
	testhelper.AssertResult(exampleT{}, e2e.Result{ExitCode: 0, Stdout: "ready"},
		e2e.Expectation{ExitCode: 0, StdoutContains: []string{"ready"}})
	testhelper.AssertResult(exampleT{}, e2e.Result{ExitCode: 1},
		e2e.Expectation{ExitCode: 0})
	// Output: unexpected result: step "result": exit code 1 is not 0
}

func ExampleAssertReport() {
	journey := e2e.Journey{
		Name: "seeds",
		Steps: []e2e.Step{{
			Name:       "seed",
			Invocation: e2e.Invocation{},
			Expect:     e2e.Expectation{ExitCode: 0},
		}},
	}
	report := e2e.Report{Driver: "scripted", Journey: "seeds", Steps: []e2e.StepReport{
		{Name: "seed", Result: e2e.Result{ExitCode: 0}},
	}}
	testhelper.AssertReport(exampleT{}, report, journey)
	fmt.Println("report matches")
	// Output: report matches
}

func ExampleAssertHarnessProblem() {
	err := exampleProblems().Raise(e2e.ProblemJourneyEmpty, "nothing to run", nil)
	envelope := testhelper.AssertHarnessProblem(exampleT{}, err, e2e.ProblemJourneyEmpty)
	fmt.Println(envelope.Status)
	// Output: 422
}

func ExampleStartStack() {
	// Nothing is booted by default: a suite pays only for the dependencies it
	// actually needs.
	_, err := testhelper.StartStack(context.Background(), testhelper.StackOptions{})
	fmt.Println(err)
	// Output: testhelper: a container stack needs at least one preset
}

func ExamplePresetFakePostgres() {
	// A block shaped like the real thing, addressing nothing, for tests that need
	// shape rather than a live dependency.
	block := testhelper.PresetFakePostgres(testhelper.PresetDefaultKey)
	entry := testhelper.PresetRequireEntry(exampleT{}, block, testhelper.PresetDefaultKey)
	fmt.Println(entry.Database, entry.Port)
	// Output: app 5432
}

func ExampleNewOtelTraceEmitter() {
	// The otel interface mocks are the only telemetry double the family ships.
	// There is no fake OTLP collector: real export is proven at SIT.
	emitter := testhelper.NewOtelTraceEmitter()
	fmt.Println(len(emitter.Records()))
	// Output: 0
}

func ExampleNewInMemoryTerminal() {
	// The re-exported interfaces mock is what lets a compiled-artifact driver be
	// tested without compiling an artifact.
	terminal := testhelper.NewInMemoryTerminal()
	fmt.Println(len(terminal.Commands()))
	// Output: 0
}
