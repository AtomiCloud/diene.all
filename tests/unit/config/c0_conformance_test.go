package config_test

import (
	"context"
	"fmt"
	"strings"
	"testing"

	"github.com/AtomiCloud/diene.go-config/lib/config"
	"github.com/AtomiCloud/diene.go-config/testhelper"
	"github.com/AtomiCloud/diene.go-core-utils/lib/coreutils"
)

// scheduleEntry mirrors a wire-typed row carried through YAML, merge, schema
// validation, and typed-slice decode.
type scheduleEntry struct {
	Date     string `json:"date"`
	Time     string `json:"time"`
	Duration string `json:"duration"`
	Zone     string `json:"zone"`
	Instant  string `json:"instant"`
}

// TestC0WireFormatsSurviveTheLoader proves ISO 8601 date/time/duration, IANA
// timezone, and RFC 3339 UTC instant values survive the full YAML to validated
// typed slice pipeline, driven by the published core-utils C0 vectors rather
// than hand-invented duplicates.
func TestC0WireFormatsSurviveTheLoader(t *testing.T) {
	t.Parallel()
	vectors := coreutils.C0Temporal
	count := minLen(
		len(vectors.Dates.Valid), len(vectors.Times.Valid),
		len(vectors.Durations.Valid), len(vectors.Timezones.Valid),
		len(vectors.Instants),
	)

	var rows strings.Builder
	for index := range count {
		fmt.Fprintf(
			&rows,
			"    - date: '%s'\n      time: '%s'\n      duration: '%s'\n      zone: '%s'\n      instant: '%s'\n",
			vectors.Dates.Valid[index], vectors.Times.Valid[index],
			vectors.Durations.Valid[index], vectors.Timezones.Valid[index],
			vectors.Instants[index].CanonicalUTC,
		)
	}
	document := testhelper.SchemaPointer + `
app:
  landscape: base
  platform: sulfoxide
  service: config
  module: lib
  version: 1.0.0
demo:
  region: local
  schedule:
` + rows.String()

	cfg, loadErr := config.NewLoader(
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(testhelper.BaseSource(document)),
		config.WithEnvSource(testhelper.EnvSource(nil)),
		config.WithSchema(testhelper.Schema()),
	).Load(context.Background())
	got := testhelper.RequireConfig(t, cfg, loadErr)

	var schedule []scheduleEntry
	if err := got.Decode("demo.schedule", &schedule); err != nil {
		t.Fatalf("decode schedule: %v", err)
	}
	if len(schedule) != count {
		t.Fatalf("expected %d schedule rows, got %d", count, len(schedule))
	}

	for index, entry := range schedule {
		date, err := coreutils.ParseWireDate(entry.Date)
		if err != nil || date.String() != vectors.Dates.Valid[index] {
			t.Fatalf("date %q did not survive: %v", entry.Date, err)
		}
		wallTime, err := coreutils.ParseWireTime(entry.Time)
		if err != nil || wallTime.String() != vectors.Times.Valid[index] {
			t.Fatalf("time %q did not survive: %v", entry.Time, err)
		}
		if _, err = coreutils.ParseIsoDuration(entry.Duration); err != nil {
			t.Fatalf("duration %q did not survive: %v", entry.Duration, err)
		}
		if _, err = coreutils.ParseIanaTimezone(entry.Zone); err != nil {
			t.Fatalf("zone %q did not survive: %v", entry.Zone, err)
		}
		instant, err := coreutils.ParseRFC3339UTC(entry.Instant)
		if err != nil {
			t.Fatalf("instant %q did not survive: %v", entry.Instant, err)
		}
		canonical, err := coreutils.FormatRFC3339UTC(instant)
		if err != nil || canonical != vectors.Instants[index].CanonicalUTC {
			t.Fatalf("instant %q did not round-trip to canonical UTC: %v", entry.Instant, err)
		}
	}
}

func minLen(values ...int) int {
	smallest := values[0]
	for _, value := range values[1:] {
		if value < smallest {
			smallest = value
		}
	}
	return smallest
}
