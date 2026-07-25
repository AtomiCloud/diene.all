package wire_test

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-api-engine/lib/wire"
)

// c0Fixture mirrors tests/fixtures/c0/wire.json. The authoritative shapes and
// samples live there so a C0-published fixture can replace them without
// touching this file.
type c0Fixture struct {
	Datetime c0Datetime `json:"datetime"`
	Duration c0Duration `json:"duration"`
	Timezone c0Timezone `json:"timezone"`
}

// c0Rendering is one input literal and the form it must render as.
type c0Rendering struct {
	Input    string `json:"input"`
	Rendered string `json:"rendered"`
}

type c0Datetime struct {
	Canonical  []c0Rendering `json:"canonical"`
	Normalized []c0Rendering `json:"normalized"`
	Rejected   []string      `json:"rejected"`
}

// c0DurationSample additionally pins the exact nanosecond value, so a literal
// cannot round-trip through a wrong magnitude unnoticed.
type c0DurationSample struct {
	Input       string `json:"input"`
	Nanoseconds int64  `json:"nanoseconds"`
	Rendered    string `json:"rendered"`
}

type c0Duration struct {
	Canonical []c0DurationSample `json:"canonical"`
	Rejected  []string           `json:"rejected"`
}

type c0Timezone struct {
	Accepted []string `json:"accepted"`
	Rejected []string `json:"rejected"`
}

func loadC0(t *testing.T) c0Fixture {
	t.Helper()
	path := filepath.Join("..", "..", "fixtures", "c0", "wire.json")
	raw, err := os.ReadFile(path) //nolint:gosec // a fixture path fixed by this test
	if err != nil {
		t.Fatalf("read C0 fixture: %v", err)
	}
	var fixture c0Fixture
	if err := json.Unmarshal(raw, &fixture); err != nil {
		t.Fatalf("decode C0 fixture: %v", err)
	}
	return fixture
}

func TestC0DatetimeIsRFC3339UTC(t *testing.T) {
	t.Parallel()
	fixture := loadC0(t)

	if len(fixture.Datetime.Canonical) == 0 {
		t.Fatal("C0 fixture declares no canonical datetimes")
	}
	for _, sample := range fixture.Datetime.Canonical {
		parsed, err := wire.ParseInstant(sample.Input)
		if err != nil {
			t.Errorf("ParseInstant(%q): unexpected error %v", sample.Input, err)
			continue
		}
		if got := parsed.String(); got != sample.Rendered {
			t.Errorf("ParseInstant(%q).String() = %q, want %q", sample.Input, got, sample.Rendered)
		}
	}
}

func TestC0DatetimeNormalizesToUTC(t *testing.T) {
	t.Parallel()
	fixture := loadC0(t)

	for _, sample := range fixture.Datetime.Normalized {
		parsed, err := wire.ParseInstant(sample.Input)
		if err != nil {
			t.Errorf("ParseInstant(%q): unexpected error %v", sample.Input, err)
			continue
		}
		// A non-UTC offset still names the same moment, so it is accepted; what
		// C0 forbids is rendering anything but the UTC form.
		if got := parsed.String(); got != sample.Rendered {
			t.Errorf("ParseInstant(%q).String() = %q, want the UTC form %q",
				sample.Input, got, sample.Rendered)
		}
	}
}

func TestC0DatetimeRejectsNonConformant(t *testing.T) {
	t.Parallel()
	fixture := loadC0(t)

	for _, sample := range fixture.Datetime.Rejected {
		if _, err := wire.ParseInstant(sample); err == nil {
			t.Errorf("ParseInstant(%q): want an error, got none", sample)
		}
	}
}

func TestC0DurationRoundTrips(t *testing.T) {
	t.Parallel()
	fixture := loadC0(t)

	if len(fixture.Duration.Canonical) == 0 {
		t.Fatal("C0 fixture declares no canonical durations")
	}
	for _, sample := range fixture.Duration.Canonical {
		parsed, err := wire.ParseDuration(sample.Input)
		if err != nil {
			t.Errorf("ParseDuration(%q): unexpected error %v", sample.Input, err)
			continue
		}
		if got := int64(parsed.Std()); got != sample.Nanoseconds {
			t.Errorf("ParseDuration(%q) = %dns, want %dns", sample.Input, got, sample.Nanoseconds)
		}
		if got := parsed.String(); got != sample.Rendered {
			t.Errorf("ParseDuration(%q).String() = %q, want %q", sample.Input, got, sample.Rendered)
		}
		// The rendered form must itself parse back to the same value, or the
		// contract is not closed under round trip.
		reparsed, err := wire.ParseDuration(parsed.String())
		if err != nil {
			t.Errorf("ParseDuration(%q): rendered form did not re-parse: %v", sample.Input, err)
			continue
		}
		if reparsed != parsed {
			t.Errorf("ParseDuration(%q): round trip drifted %v -> %v", sample.Input, parsed, reparsed)
		}
	}
}

func TestC0DurationRejectsNonConformant(t *testing.T) {
	t.Parallel()
	fixture := loadC0(t)

	for _, sample := range fixture.Duration.Rejected {
		if _, err := wire.ParseDuration(sample); err == nil {
			t.Errorf("ParseDuration(%q): want an error, got none", sample)
		}
	}
}

func TestC0TimezoneAcceptsIANAIdentifiers(t *testing.T) {
	t.Parallel()
	fixture := loadC0(t)

	if len(fixture.Timezone.Accepted) == 0 {
		t.Fatal("C0 fixture declares no accepted timezones")
	}
	for _, sample := range fixture.Timezone.Accepted {
		zone, err := wire.ParseZone(sample)
		if err != nil {
			t.Errorf("ParseZone(%q): unexpected error %v", sample, err)
			continue
		}
		if zone.String() != sample {
			t.Errorf("ParseZone(%q).String() = %q, want the identifier back", sample, zone.String())
		}
		location, err := zone.Location()
		if err != nil {
			t.Errorf("Zone(%q).Location(): unexpected error %v", sample, err)
			continue
		}
		if location.String() != sample {
			t.Errorf("Zone(%q).Location() = %q, want %q", sample, location.String(), sample)
		}
	}
}

func TestC0TimezoneRejectsOffsetsAndAbbreviations(t *testing.T) {
	t.Parallel()
	fixture := loadC0(t)

	for _, sample := range fixture.Timezone.Rejected {
		if _, err := wire.ParseZone(sample); err == nil {
			t.Errorf("ParseZone(%q): want an error, got none", sample)
		}
	}
}

func TestC0WireTypesRoundTripThroughJSON(t *testing.T) {
	t.Parallel()

	type payload struct {
		At    wire.Instant  `json:"at"`
		Every wire.Duration `json:"every"`
		Zone  wire.Zone     `json:"zone"`
	}

	moment := time.Date(2026, 7, 25, 19, 35, 0, 0, time.UTC)
	original := payload{
		At:    wire.NewInstant(moment),
		Every: wire.Duration(90 * time.Second),
		Zone:  wire.Zone("Asia/Singapore"),
	}

	encoded, err := json.Marshal(original)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	const want = `{"at":"2026-07-25T19:35:00Z","every":"PT1M30S","zone":"Asia/Singapore"}`
	if string(encoded) != want {
		t.Errorf("marshal = %s, want %s", encoded, want)
	}

	var decoded payload
	if err := json.Unmarshal(encoded, &decoded); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if !decoded.At.Std().Equal(moment) {
		t.Errorf("instant round trip: got %v, want %v", decoded.At.Std(), moment)
	}
	if decoded.Every != original.Every {
		t.Errorf("duration round trip: got %v, want %v", decoded.Every, original.Every)
	}
	if decoded.Zone != original.Zone {
		t.Errorf("zone round trip: got %v, want %v", decoded.Zone, original.Zone)
	}
}

func TestC0WireTypesRejectBadJSON(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name   string
		json   string
		target any
	}{
		{"instant not a string", `5`, new(wire.Instant)},
		{"instant not RFC 3339", `"25-07-2026"`, new(wire.Instant)},
		{"duration not a string", `5`, new(wire.Duration)},
		{"duration not ISO 8601", `"1h30m"`, new(wire.Duration)},
		{"zone not a string", `5`, new(wire.Zone)},
		{"zone is an offset", `"+08:00"`, new(wire.Zone)},
	}
	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			t.Parallel()
			if err := json.Unmarshal([]byte(testCase.json), testCase.target); err == nil {
				t.Errorf("Unmarshal(%s): want an error, got none", testCase.json)
			}
		})
	}
}
