package e2e_test

import (
	"context"
	"errors"
	"fmt"
	"io"
	"strings"

	"github.com/AtomiCloud/diene.go-e2e/lib/e2e"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

// greeter is the in-process composition root the examples drive. A real service
// would build its container here and run it; the shape is the same.
func greeter(_ context.Context, invocation e2e.Invocation, stdout io.Writer, stderr io.Writer) (int, error) {
	if len(invocation.Args) == 0 {
		if _, err := io.WriteString(stderr, "usage: greet <name>"); err != nil {
			return 0, err
		}
		return 2, nil
	}
	if _, err := io.WriteString(stdout, "hello "+strings.Join(invocation.Args, " ")); err != nil {
		return 0, err
	}
	return 0, nil
}

// exampleProblems builds the harness problem factory from a service's own error
// portal.
func exampleProblems() *e2e.Problems {
	problems, err := e2e.NewProblems(problem.LocalErrorPortal())
	if err != nil {
		panic(err)
	}
	return problems
}

func ExampleNewInProcessDriver() {
	driver, err := e2e.NewInProcessDriver(e2e.InProcessOptions{
		Entrypoint: greeter,
		Problems:   exampleProblems(),
	})
	if err != nil {
		panic(err)
	}
	result, err := driver.Run(context.Background(), e2e.Invocation{Args: []string{"world"}})
	if err != nil {
		panic(err)
	}
	fmt.Println(driver.Name(), result.ExitCode, result.Stdout)
	// Output: in-process 0 hello world
}

func ExampleRunJourney() {
	driver, err := e2e.NewInProcessDriver(e2e.InProcessOptions{
		Entrypoint: greeter,
		Problems:   exampleProblems(),
	})
	if err != nil {
		panic(err)
	}
	journey := e2e.Journey{
		Name: "greets-and-refuses",
		Steps: []e2e.Step{
			{
				Name:       "greets a name",
				Invocation: e2e.Invocation{Args: []string{"world"}},
				Expect:     e2e.Expectation{ExitCode: 0, StdoutContains: []string{"hello world"}},
			},
			{
				Name:       "refuses no name",
				Invocation: e2e.Invocation{},
				Expect:     e2e.Expectation{ExitCode: 2, StderrContains: []string{"usage:"}},
			},
		},
	}
	report, err := e2e.RunJourney(context.Background(), driver, journey, exampleProblems())
	if err != nil {
		panic(err)
	}
	fmt.Println(report.Journey, len(report.Steps))
	// Output: greets-and-refuses 2
}

func ExampleCheckStep() {
	step := e2e.Step{
		Name:       "greets a name",
		Invocation: e2e.Invocation{Args: []string{"world"}},
		Expect:     e2e.Expectation{ExitCode: 0, StdoutContains: []string{"hello world"}},
	}
	fmt.Println(e2e.CheckStep(step, e2e.Result{ExitCode: 0, Stdout: "hello world"}))
	fmt.Println(e2e.CheckStep(step, e2e.Result{ExitCode: 1, Stdout: "hello world"}))
	// Output:
	// <nil>
	// step "greets a name": exit code 1 is not 0
}

func ExampleCompareReports() {
	// Streams may differ between a subprocess and an in-process run; which steps
	// ran and how each ended may not.
	compiled := e2e.Report{Driver: "compiled", Journey: "greets", Steps: []e2e.StepReport{
		{Name: "greets a name", Result: e2e.Result{ExitCode: 0, Stdout: "hello world\n"}},
	}}
	inProcess := e2e.Report{Driver: "in-process", Journey: "greets", Steps: []e2e.StepReport{
		{Name: "greets a name", Result: e2e.Result{ExitCode: 0, Stdout: "hello world"}},
	}}
	fmt.Println(e2e.CompareReports(compiled, inProcess, exampleProblems()))
	// Output: <nil>
}

func ExampleProblems_Raise() {
	err := exampleProblems().Raise(e2e.ProblemJourneyEmpty, "a journey with no steps proves nothing", nil)
	var typed *problem.Error
	if !errors.As(err, &typed) {
		panic("expected a problem-typed error")
	}
	fmt.Println(typed.Problem.Status)
	fmt.Println(typed.Problem.Type)
	// Output:
	// 422
	// https://local.atomi.cloud/docs/local/go/app/core/v1/journey-empty
}

func ExampleProblemTypes() {
	for _, declared := range e2e.ProblemTypes()[:3] {
		fmt.Println(declared.ID, declared.Status)
	}
	// Output:
	// driver-unconfigured 500
	// artifact-missing 500
	// invocation-failed 500
}

func ExampleResult_Succeeded() {
	fmt.Println(e2e.Result{ExitCode: 0}.Succeeded(), e2e.Result{ExitCode: 1}.Succeeded())
	// Output: true false
}
