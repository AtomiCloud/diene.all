package sit_test

import (
	"maps"
	"testing"

	"github.com/AtomiCloud/diene.go-e2e/lib/e2e"
)

func TestHealthJourney(t *testing.T) {
	harness := newSITHarness(t)
	id := newUUID(t)
	workerEnv := workerEnvironment("health", id)
	healthEnv := make(map[string]string, len(workerEnv)+3)
	maps.Copy(healthEnv, workerEnv)
	healthEnv["ATOMI_POSTGRES__MAIN__HOST"] = "dependency-is-not-consulted.invalid"
	healthEnv["ATOMI_KV__MAIN__HOST"] = "dependency-is-not-consulted.invalid"
	healthEnv["ATOMI_STORAGE__MAIN__ENDPOINT"] = "http://dependency-is-not-consulted.invalid"
	journey := e2e.Journey{
		Name: "dependency-blind health",
		Steps: []e2e.Step{
			{
				Name:       "initialize dependencies",
				Invocation: harness.invocation(nil, "db-init"),
				Expect:     e2e.Expectation{ExitCode: 0, StdoutContains: []string{`"ok":true`}},
			},
			{
				Name:       "write a healthy heartbeat",
				Invocation: harness.invocation(workerEnv, "worker", "--once"),
				Expect:     e2e.Expectation{ExitCode: 0, StdoutExcludes: []string{"dependency unavailable"}},
			},
			{
				Name:       "check health without dialing dependencies",
				Invocation: harness.invocation(healthEnv, "health"),
				Expect: e2e.Expectation{
					ExitCode:       0,
					StdoutContains: []string{`"healthy":true`},
					StdoutExcludes: []string{"dependency-is-not-consulted.invalid"},
				},
			},
		},
	}
	harness.run(t, journey)
}
