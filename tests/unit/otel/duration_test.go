package otel_test

import (
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-otel/lib/otel"
)

func TestParseFixedDuration(t *testing.T) {
	t.Parallel()

	tests := map[string]time.Duration{
		"PT10S":        10 * time.Second,
		"PT60S":        time.Minute,
		"PT0.5S":       500 * time.Millisecond,
		"PT0,5S":       500 * time.Millisecond,
		"P1DT2H3M4.5S": 26*time.Hour + 3*time.Minute + 4500*time.Millisecond,
		"P1W":          7 * 24 * time.Hour,
	}
	for input, want := range tests {
		got, err := otel.ParseFixedDuration(input)
		if err != nil {
			t.Errorf("ParseFixedDuration(%q): %v", input, err)
			continue
		}
		if got != want {
			t.Errorf("ParseFixedDuration(%q): want %s, got %s", input, want, got)
		}
	}
	for _, input := range append(otel.C0Otel.InvalidDurations,
		"P999999999999999999999999999999999999999W") {
		_, err := otel.ParseFixedDuration(input)
		assertProblemID(t, err, otel.FaultDurationInvalid)
	}
}

func TestIsoComponentSeconds(t *testing.T) {
	t.Parallel()

	got, err := otel.IsoComponentSeconds("1H2M3.5S", map[byte]float64{
		'H': 3600,
		'M': 60,
		'S': 1,
	}, "PT1H2M3.5S")
	if err != nil {
		t.Fatalf("expected components to parse: %v", err)
	}
	if got != 3723.5 {
		t.Fatalf("expected 3723.5 seconds, got %v", got)
	}
	for _, section := range []string{"1Q", "H", "1.2.3S", "10"} {
		_, parseErr := otel.IsoComponentSeconds(section, map[byte]float64{'S': 1}, section)
		assertProblemID(t, parseErr, otel.FaultDurationInvalid)
	}
}
