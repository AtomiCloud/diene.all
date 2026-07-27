package sit_test

import (
	"testing"

	"github.com/AtomiCloud/diene.go-e2e/lib/e2e"
)

func TestWorkerModeJourney(t *testing.T) {
	harness := newSITHarness(t)
	id := newUUID(t)
	environment := workerEnvironment("worker", id)
	journey := e2e.Journey{
		Name: "worker mode",
		Steps: []e2e.Step{
			{
				Name:       "initialize dependencies",
				Invocation: harness.invocation(nil, "db-init"),
				Expect:     e2e.Expectation{ExitCode: 0, StdoutContains: []string{`"ok":true`}},
			},
			{
				Name:       "run one worker cycle",
				Invocation: harness.invocation(environment, "worker", "--once"),
				Expect: e2e.Expectation{
					ExitCode:       0,
					StdoutExcludes: []string{"dependency unavailable", "unknown command"},
				},
			},
			{
				Name:       "observe the worker heartbeat",
				Invocation: harness.invocation(environment, "health"),
				Expect:     e2e.Expectation{ExitCode: 0, StdoutContains: []string{`"healthy":true`}},
			},
		},
	}
	harness.run(t, journey)
}
