package sit_test

import (
	"context"
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-e2e/lib/e2e"
)

func TestDBInitModeJourney(t *testing.T) {
	harness := newSITHarness(t)
	journey := e2e.Journey{
		Name: "db-init mode",
		Steps: []e2e.Step{{
			Name:       "reach dependencies migrate and seed",
			Invocation: harness.invocation(map[string]string{"ATOMI_DB_INIT__CREATE_BUCKET": "true"}, "db-init"),
			Expect:     e2e.Expectation{ExitCode: 0, StdoutContains: []string{`"ok":true`}},
		}},
	}
	harness.run(t, journey)

	ctx, cancel := context.WithTimeout(t.Context(), 15*time.Second)
	defer cancel()
	database := postgresClient(ctx, t)
	var migrations int
	var seeds int
	if err := database.QueryRow(ctx, "SELECT COUNT(*) FROM diene_migrations").Scan(&migrations); err != nil {
		t.Fatalf("count applied migrations: %v", err)
	}
	if err := database.QueryRow(ctx, "SELECT COUNT(*) FROM seed_records").Scan(&seeds); err != nil {
		t.Fatalf("count seed records: %v", err)
	}
	if migrations < 1 || seeds < 1 {
		t.Fatalf("db-init evidence = %d migrations, %d seeds; both must be positive", migrations, seeds)
	}
}
