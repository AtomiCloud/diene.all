package wire

import (
	"errors"
	"strconv"
	"time"
)

// ErrInstant reports a value that is not an RFC 3339 UTC instant.
var ErrInstant = errors.New("wire: not an RFC 3339 UTC instant")

// ErrZone reports a value that is not an IANA timezone identifier.
//
// A UTC offset such as `+08:00` and an abbreviation such as `SGT` are both
// rejected: an offset discards which zone produced it, and an abbreviation is
// ambiguous across regions, so neither can be resolved back to the political
// rules a future timestamp must be interpreted under.
var ErrZone = errors.New("wire: not an IANA timezone identifier")

// Instant is a [time.Time] that crosses the wire as an RFC 3339 UTC instant
// (C0 §1), e.g. `2026-07-25T19:35:00Z`.
//
// Rendering always normalizes to UTC, so the same moment produces the same
// bytes regardless of the location the value was constructed in — which is what
// makes an instant comparable across services.
type Instant time.Time

// NewInstant returns the instant for moment.
func NewInstant(moment time.Time) Instant { return Instant(moment) }

// Std returns the instant as a standard [time.Time] in UTC.
func (i Instant) Std() time.Time { return time.Time(i).UTC() }

// String renders the RFC 3339 UTC form, keeping any sub-second precision the
// instant carries.
func (i Instant) String() string {
	return time.Time(i).UTC().Format(time.RFC3339Nano)
}

// ParseInstant parses an RFC 3339 timestamp and normalizes it to UTC.
//
// A timestamp carrying a non-UTC offset is accepted and converted, because the
// offset still identifies the same moment; what C0 forbids is *rendering* a
// non-UTC form, which [Instant.String] cannot do.
func ParseInstant(value string) (Instant, error) {
	parsed, err := time.Parse(time.RFC3339, value)
	if err != nil {
		return Instant{}, ErrInstant
	}
	return Instant(parsed.UTC()), nil
}

// MarshalJSON renders the instant as a JSON string in RFC 3339 UTC form.
func (i Instant) MarshalJSON() ([]byte, error) {
	return []byte(strconv.Quote(i.String())), nil
}

// UnmarshalJSON reads an RFC 3339 timestamp from a JSON string.
func (i *Instant) UnmarshalJSON(data []byte) error {
	text, err := strconv.Unquote(string(data))
	if err != nil {
		return ErrInstant
	}
	parsed, err := ParseInstant(text)
	if err != nil {
		return err
	}
	*i = parsed
	return nil
}

// Zone is an IANA timezone identifier, e.g. `Asia/Singapore`.
type Zone string

// String returns the identifier.
func (z Zone) String() string { return string(z) }

// Location resolves the identifier against the platform's zone database.
func (z Zone) Location() (*time.Location, error) {
	location, err := time.LoadLocation(string(z))
	if err != nil {
		return nil, ErrZone
	}
	return location, nil
}

// ParseZone validates that value is an IANA identifier and returns it.
//
// `UTC` is accepted because it is a genuine database entry; the empty string
// and `Local` are rejected, the first because a blank value is unset (M33) and
// the second because it names the reader's machine rather than a zone.
func ParseZone(value string) (Zone, error) {
	if value == "" || value == "Local" {
		return "", ErrZone
	}
	if _, err := time.LoadLocation(value); err != nil {
		return "", ErrZone
	}
	return Zone(value), nil
}

// MarshalJSON renders the zone as a JSON string.
func (z Zone) MarshalJSON() ([]byte, error) {
	return []byte(strconv.Quote(string(z))), nil
}

// UnmarshalJSON reads and validates an IANA identifier from a JSON string.
func (z *Zone) UnmarshalJSON(data []byte) error {
	text, err := strconv.Unquote(string(data))
	if err != nil {
		return ErrZone
	}
	parsed, err := ParseZone(text)
	if err != nil {
		return err
	}
	*z = parsed
	return nil
}
