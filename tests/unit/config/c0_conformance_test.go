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

// c0Schema composes the app block with a demo block whose schedule items are
// format-constrained by the C0 wire formats, so invalid temporal values are
// rejected at validation time rather than only at post-decode parsing.
func c0Schema() config.Schema {
	stringWithFormat := func(format string) map[string]any {
		return map[string]any{"type": "string", "format": format}
	}
	scheduleItem := map[string]any{
		"type": "object",
		"properties": map[string]any{
			"date":     stringWithFormat("wire-date"),
			"time":     stringWithFormat("wire-time"),
			"duration": stringWithFormat("iso-duration"),
			"zone":     stringWithFormat("iana-time-zone"),
			"instant":  stringWithFormat("rfc3339-utc"),
		},
		"required":             []any{"date", "time", "duration", "zone", "instant"},
		"additionalProperties": false,
	}
	demo := config.NewBlock("demo", true, map[string]any{
		"type": "object",
		"properties": map[string]any{
			"region":   map[string]any{"type": "string", "minLength": float64(1)},
			"schedule": map[string]any{"type": "array", "items": scheduleItem},
		},
		"required":             []any{"region"},
		"additionalProperties": true,
	})
	return config.ComposeSchema(config.AppBlockSchema(), demo)
}

// c0Document builds a base document carrying one schedule row.
func c0Document(entries ...scheduleEntry) string {
	var rows strings.Builder
	for _, entry := range entries {
		fmt.Fprintf(
			&rows,
			"    - date: '%s'\n      time: '%s'\n      duration: '%s'\n      zone: '%s'\n      instant: '%s'\n",
			entry.Date, entry.Time, entry.Duration, entry.Zone, entry.Instant,
		)
	}
	return testhelper.SchemaPointer + `
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
}

func loadC0(t *testing.T, document string) (*config.Config, error) {
	t.Helper()
	return config.NewLoader(
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(testhelper.BaseSource(document)),
		config.WithEnvSource(testhelper.EnvSource(nil)),
		config.WithSchema(c0Schema()),
	).Load(context.Background())
}

// TestC0ValidVectorsSurviveTheLoader proves valid ISO 8601 date/time/duration
// and IANA timezone values pass schema validation and survive to a typed slice,
// driven by the published core-utils C0 vectors.
func TestC0ValidVectorsSurviveTheLoader(t *testing.T) {
	t.Parallel()
	vectors := coreutils.C0Temporal
	count := minLen(
		len(vectors.Dates.Valid), len(vectors.Times.Valid),
		len(vectors.Durations.Valid), len(vectors.Timezones.Valid),
		len(vectors.Instants),
	)
	entries := make([]scheduleEntry, count)
	for index := range count {
		entries[index] = scheduleEntry{
			Date:     vectors.Dates.Valid[index],
			Time:     vectors.Times.Valid[index],
			Duration: vectors.Durations.Valid[index],
			Zone:     vectors.Timezones.Valid[index],
			Instant:  vectors.Instants[index].CanonicalUTC,
		}
	}

	cfg, loadErr := loadC0(t, c0Document(entries...))
	got := testhelper.RequireConfig(t, cfg, loadErr)

	var schedule []scheduleEntry
	if err := got.Decode("demo.schedule", &schedule); err != nil {
		t.Fatalf("decode schedule: %v", err)
	}
	if len(schedule) != count {
		t.Fatalf("expected %d rows, got %d", count, len(schedule))
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

// TestC0InvalidVectorsAreRejected proves the schema — not only post-decode
// parsing — rejects malformed wire values, one C0 invalid vector at a time.
func TestC0InvalidVectorsAreRejected(t *testing.T) {
	t.Parallel()
	vectors := coreutils.C0Temporal
	valid := scheduleEntry{
		Date: "2026-07-21", Time: "01:02:03", Duration: "P1DT2H",
		Zone: "Asia/Singapore", Instant: "2026-07-21T01:02:03.000Z",
	}

	fields := []struct {
		name    string
		invalid []string
		apply   func(scheduleEntry, string) scheduleEntry
	}{
		{"date", vectors.Dates.Invalid, func(e scheduleEntry, v string) scheduleEntry { e.Date = v; return e }},
		{"time", vectors.Times.Invalid, func(e scheduleEntry, v string) scheduleEntry { e.Time = v; return e }},
		{"duration", vectors.Durations.Invalid, func(e scheduleEntry, v string) scheduleEntry { e.Duration = v; return e }},
		{"zone", vectors.Timezones.Invalid, func(e scheduleEntry, v string) scheduleEntry { e.Zone = v; return e }},
		{"instant", vectors.InvalidInstants, func(e scheduleEntry, v string) scheduleEntry { e.Instant = v; return e }},
	}
	for _, field := range fields {
		for _, bad := range field.invalid {
			// A single-quoted YAML scalar keeps the invalid value a string.
			if strings.ContainsAny(bad, "'\n") {
				continue
			}
			entry := field.apply(valid, bad)
			cfg, err := loadC0(t, c0Document(entry))
			loadErr := testhelper.RequireLoadError(t, cfg, err)
			if _, ok := config.ValidationIssues(loadErr); !ok {
				t.Fatalf("invalid %s %q must be a validation problem, got %v", field.name, bad, loadErr)
			}
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
