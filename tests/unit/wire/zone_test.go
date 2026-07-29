package wire_test

import (
	"errors"
	"testing"

	"github.com/AtomiCloud/diene.go-api-engine/lib/wire"
)

// A Zone can be constructed directly from an untrusted string — a config field
// unmarshalled by something other than this package, say — so resolving one has
// to fail rather than panic.
func TestZoneLocationRejectsAnUnvalidatedIdentifier(t *testing.T) {
	t.Parallel()

	if _, err := wire.Zone("Not/AZone").Location(); !errors.Is(err, wire.ErrZone) {
		t.Errorf("Location() error = %v, want ErrZone", err)
	}
}

func TestZoneLocationResolvesUTC(t *testing.T) {
	t.Parallel()

	location, err := wire.Zone("UTC").Location()
	if err != nil {
		t.Fatalf("Location(): unexpected error %v", err)
	}
	if location.String() != "UTC" {
		t.Errorf("Location() = %q, want %q", location.String(), "UTC")
	}
}

// The sentinel errors are part of the public contract: a consumer switches on
// them rather than on message text.
func TestParseErrorsAreSentinels(t *testing.T) {
	t.Parallel()

	if _, err := wire.ParseInstant("nope"); !errors.Is(err, wire.ErrInstant) {
		t.Errorf("ParseInstant error = %v, want ErrInstant", err)
	}
	if _, err := wire.ParseDuration("nope"); !errors.Is(err, wire.ErrDuration) {
		t.Errorf("ParseDuration error = %v, want ErrDuration", err)
	}
	if _, err := wire.ParseZone("nope"); !errors.Is(err, wire.ErrZone) {
		t.Errorf("ParseZone error = %v, want ErrZone", err)
	}
}
