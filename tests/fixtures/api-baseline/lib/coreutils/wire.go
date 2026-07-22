package coreutils

import (
	"fmt"
	"regexp"
	"time"
)

var (
	wireDatePattern    = regexp.MustCompile(`^([0-9]{4})-([0-9]{2})-([0-9]{2})$`)
	wireTimePattern    = regexp.MustCompile(`^([0-9]{2}):([0-9]{2}):([0-9]{2})$`)
	wireInstantPattern = regexp.MustCompile(`^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]+)?Z$`)
	isoDurationPattern = regexp.MustCompile(`^P(?:(?:[0-9]+(?:[.,][0-9]+)?Y)?(?:[0-9]+(?:[.,][0-9]+)?M)?(?:[0-9]+(?:[.,][0-9]+)?W)?(?:[0-9]+(?:[.,][0-9]+)?D)?)(?:T(?:[0-9]+(?:[.,][0-9]+)?H)?(?:[0-9]+(?:[.,][0-9]+)?M)?(?:[0-9]+(?:[.,][0-9]+)?S)?)?$`)
)

// WireDate is a validated C0 YYYY-MM-DD calendar date.
type WireDate struct {
	// Year is in the inclusive range 1 through 9999.
	Year int
	// Month is the calendar month.
	Month int
	// Day is the day within Month.
	Day int
}

// NewWireDate validates and creates a WireDate.
func NewWireDate(year int, month int, day int) (WireDate, error) {
	value := time.Date(year, time.Month(month), day, 0, 0, 0, 0, time.UTC)
	if year < 1 || year > 9999 || int(value.Month()) != month || value.Day() != day {
		return WireDate{}, fmt.Errorf("expected a valid calendar date: %d-%d-%d", year, month, day)
	}
	return WireDate{Year: year, Month: month, Day: day}, nil
}

// ParseWireDate parses a strict YYYY-MM-DD calendar date.
func ParseWireDate(value string) (WireDate, error) {
	parts := wireDatePattern.FindStringSubmatch(value)
	if parts == nil {
		return WireDate{}, fmt.Errorf("expected YYYY-MM-DD: %q", value)
	}
	var year, month, day int
	_, _ = fmt.Sscanf(value, "%d-%d-%d", &year, &month, &day)
	return NewWireDate(year, month, day)
}

// String formats WireDate in canonical YYYY-MM-DD form.
func (value WireDate) String() string {
	return fmt.Sprintf("%04d-%02d-%02d", value.Year, value.Month, value.Day)
}

// WireTime is a validated C0 HH:mm:ss wall-clock time.
type WireTime struct {
	// Hour is in the inclusive range 0 through 23.
	Hour int
	// Minute is in the inclusive range 0 through 59.
	Minute int
	// Second is in the inclusive range 0 through 59.
	Second int
}

// NewWireTime validates and creates a WireTime.
func NewWireTime(hour int, minute int, second int) (WireTime, error) {
	if hour < 0 || hour > 23 || minute < 0 || minute > 59 || second < 0 || second > 59 {
		return WireTime{}, fmt.Errorf("expected a valid wall-clock time: %d:%d:%d", hour, minute, second)
	}
	return WireTime{Hour: hour, Minute: minute, Second: second}, nil
}

// ParseWireTime parses a strict HH:mm:ss wall-clock time.
func ParseWireTime(value string) (WireTime, error) {
	if !wireTimePattern.MatchString(value) {
		return WireTime{}, fmt.Errorf("expected HH:mm:ss: %q", value)
	}
	var hour, minute, second int
	_, _ = fmt.Sscanf(value, "%d:%d:%d", &hour, &minute, &second)
	return NewWireTime(hour, minute, second)
}

// String formats WireTime in canonical HH:mm:ss form.
func (value WireTime) String() string {
	return fmt.Sprintf("%02d:%02d:%02d", value.Hour, value.Minute, value.Second)
}

// IsoDuration is a validated ISO 8601 duration kept as text to avoid lossy conversion.
type IsoDuration struct {
	value string
}

// ParseIsoDuration validates an ISO 8601 duration and normalizes decimal commas.
func ParseIsoDuration(value string) (IsoDuration, error) {
	if value == "P" || value == "PT" || !isoDurationPattern.MatchString(value) {
		return IsoDuration{}, fmt.Errorf("expected an ISO 8601 duration: %q", value)
	}
	return IsoDuration{value: regexp.MustCompile(",").ReplaceAllString(value, ".")}, nil
}

// String returns the canonical duration text.
func (value IsoDuration) String() string {
	return value.value
}

// IanaTimezone is a validated IANA timezone identifier.
type IanaTimezone struct {
	value string
}

// ParseIanaTimezone validates an IANA timezone identifier.
func ParseIanaTimezone(value string) (IanaTimezone, error) {
	if !IsIanaTimezone(value) {
		return IanaTimezone{}, fmt.Errorf("expected an IANA timezone identifier: %q", value)
	}
	return IanaTimezone{value: value}, nil
}

// String returns the original IANA identifier.
func (value IanaTimezone) String() string {
	return value.value
}

// FormatRFC3339UTC formats value as a canonical millisecond RFC 3339 UTC instant.
func FormatRFC3339UTC(value time.Time) (string, error) {
	utc := value.UTC()
	if utc.Year() < 1 || utc.Year() > 9999 {
		return "", fmt.Errorf("expected a valid calendar date: %s", utc)
	}
	return utc.Format("2006-01-02T15:04:05.000Z"), nil
}

// ParseRFC3339UTC parses a strict RFC 3339 instant ending in Z.
func ParseRFC3339UTC(value string) (time.Time, error) {
	if !wireInstantPattern.MatchString(value) {
		return time.Time{}, fmt.Errorf("expected an RFC 3339 UTC instant: %q", value)
	}
	parsed, errorValue := time.Parse(time.RFC3339Nano, value)
	if errorValue != nil {
		return time.Time{}, fmt.Errorf("expected an RFC 3339 UTC instant: %q", value)
	}
	return parsed.UTC(), nil
}

// WireCodec encodes and decodes the C0 temporal wire forms.
type WireCodec struct{}

// EncodeDate encodes a WireDate.
func (WireCodec) EncodeDate(value WireDate) string { return value.String() }

// DecodeDate decodes a WireDate.
func (WireCodec) DecodeDate(value string) (WireDate, error) { return ParseWireDate(value) }

// EncodeTime encodes a WireTime.
func (WireCodec) EncodeTime(value WireTime) string { return value.String() }

// DecodeTime decodes a WireTime.
func (WireCodec) DecodeTime(value string) (WireTime, error) { return ParseWireTime(value) }

// EncodeInstant encodes a UTC instant.
func (WireCodec) EncodeInstant(value time.Time) (string, error) { return FormatRFC3339UTC(value) }

// DecodeInstant decodes a UTC instant.
func (WireCodec) DecodeInstant(value string) (time.Time, error) { return ParseRFC3339UTC(value) }

// EncodeDuration encodes an ISO duration.
func (WireCodec) EncodeDuration(value IsoDuration) string { return value.String() }

// DecodeDuration decodes an ISO duration.
func (WireCodec) DecodeDuration(value string) (IsoDuration, error) { return ParseIsoDuration(value) }

// EncodeTimezone encodes an IANA timezone.
func (WireCodec) EncodeTimezone(value IanaTimezone) string { return value.String() }

// DecodeTimezone decodes an IANA timezone.
func (WireCodec) DecodeTimezone(value string) (IanaTimezone, error) { return ParseIanaTimezone(value) }
