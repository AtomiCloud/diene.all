package sit_test

import (
	"context"
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-e2e/lib/e2e"
)

func TestDBInitIdempotencyJourney(t *testing.T) {
	harness := newSITHarness(t)
	journey := e2e.Journey{
		Name: "db-init idempotency",
		Steps: []e2e.Step{
			{
				Name:       "initialize once",
				Invocation: harness.invocation(nil, "db-init"),
				Expect:     e2e.Expectation{ExitCode: 0, StdoutContains: []string{`"ok":true`}},
			},
			{
				Name:       "initialize without duplicate seeds",
				Invocation: harness.invocation(nil, "db-init"),
				Expect: e2e.Expectation{
					ExitCode:       0,
					StdoutContains: []string{`"ok":true`, `"seeded":0`},
				},
			},
		},
	}
	harness.run(t, journey)

	ctx, cancel := context.WithTimeout(t.Context(), 15*time.Second)
	defer cancel()
	database := postgresClient(ctx, t)
	var total int
	var distinct int
	if err := database.QueryRow(ctx, "SELECT COUNT(*), COUNT(DISTINCT id) FROM seed_records").Scan(&total, &distinct); err != nil {
		t.Fatalf("count seed records: %v", err)
	}
	if total == 0 || total != distinct {
		t.Fatalf("seed rows = %d total and %d distinct; expected a non-empty duplicate-free set", total, distinct)
	}
}
