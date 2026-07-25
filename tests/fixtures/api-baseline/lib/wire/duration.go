package wire

import (
	"errors"
	"strconv"
	"strings"
	"time"
)

// ErrDuration reports a value that is not a C0-shaped ISO 8601 duration.
//
// It is returned for a malformed literal and for the calendar designators `Y`
// and `M` (year and month), which C0 durations exclude: a year and a month have
// no fixed length, so a timeout expressed in them cannot be converted to an
// exact [time.Duration] without a calendar and a reference instant.
var ErrDuration = errors.New("wire: not an ISO 8601 duration")

// Duration is a [time.Duration] that crosses the wire as an ISO 8601 duration
// (C0 §1), e.g. `PT10S` for ten seconds.
//
// Go's own [time.Duration] marshals as an integer nanosecond count, which no
// other language in the family reads, so every duration in a config block or a
// payload uses this type instead.
type Duration time.Duration

// Std returns the duration as a standard [time.Duration].
func (d Duration) Std() time.Duration { return time.Duration(d) }

// String renders the ISO 8601 form, e.g. `PT1H30M` or `-PT0.5S`.
//
// Zero renders as `PT0S` rather than the bare `P` an empty component list would
// otherwise produce, because `P` is not a legal duration.
func (d Duration) String() string {
	remaining := time.Duration(d)
	if remaining == 0 {
		return "PT0S"
	}

	var out strings.Builder
	if remaining < 0 {
		out.WriteByte('-')
		remaining = -remaining
	}
	out.WriteByte('P')

	if days := remaining / (24 * time.Hour); days > 0 {
		out.WriteString(strconv.FormatInt(int64(days), 10))
		out.WriteByte('D')
		remaining -= days * 24 * time.Hour
	}
	if remaining == 0 {
		return out.String()
	}

	out.WriteByte('T')
	if hours := remaining / time.Hour; hours > 0 {
		out.WriteString(strconv.FormatInt(int64(hours), 10))
		out.WriteByte('H')
		remaining -= hours * time.Hour
	}
	if minutes := remaining / time.Minute; minutes > 0 {
		out.WriteString(strconv.FormatInt(int64(minutes), 10))
		out.WriteByte('M')
		remaining -= minutes * time.Minute
	}
	if remaining > 0 {
		seconds := remaining.Seconds()
		out.WriteString(strconv.FormatFloat(seconds, 'f', -1, 64))
		out.WriteByte('S')
	}
	return out.String()
}

// ParseDuration parses the ISO 8601 duration form produced by
// [Duration.String].
//
// It accepts an optional leading sign, the day designator, and the hour,
// minute, and second designators after `T`; seconds may carry a fraction. It
// rejects `Y` and `M` in the date half for the reason given on [ErrDuration],
// and rejects a designator that repeats or appears out of order, because both
// signal a typo rather than an intended value.
func ParseDuration(value string) (Duration, error) {
	body, negative, err := durationSign(value)
	if err != nil {
		return 0, err
	}
	datePart, timePart, err := durationHalves(body)
	if err != nil {
		return 0, err
	}

	total, err := durationDays(datePart)
	if err != nil {
		return 0, err
	}
	timeTotal, err := durationTime(timePart)
	if err != nil {
		return 0, err
	}
	total += timeTotal

	if negative {
		total = -total
	}
	return Duration(total), nil
}

// durationSign strips the optional sign and the mandatory `P`.
func durationSign(value string) (string, bool, error) {
	negative := false
	switch {
	case strings.HasPrefix(value, "-"):
		negative = true
		value = value[1:]
	case strings.HasPrefix(value, "+"):
		value = value[1:]
	default:
		// An unsigned duration is positive, which is the common case.
	}
	if !strings.HasPrefix(value, "P") {
		return "", false, ErrDuration
	}
	return value[1:], negative, nil
}

// durationHalves splits the body at `T` into its date and time halves,
// rejecting a body that carries no component at all.
func durationHalves(body string) (datePart string, timePart string, err error) {
	datePart, timePart, split := strings.Cut(body, "T")
	if datePart == "" && timePart == "" {
		return "", "", ErrDuration
	}
	if split && timePart == "" {
		return "", "", ErrDuration
	}
	return datePart, timePart, nil
}

// durationDays converts the date half, which C0 restricts to whole days.
func durationDays(datePart string) (time.Duration, error) {
	if datePart == "" {
		return 0, nil
	}
	digits, ok := strings.CutSuffix(datePart, "D")
	if !ok {
		return 0, ErrDuration
	}
	days, err := strconv.ParseFloat(digits, 64)
	if err != nil || days < 0 {
		return 0, ErrDuration
	}
	return time.Duration(days * float64(24*time.Hour)), nil
}

// durationTime converts the time half, enforcing H/M/S order and no repeats.
func durationTime(timePart string) (time.Duration, error) {
	if timePart == "" {
		return 0, nil
	}
	units := []struct {
		designator byte
		scale      time.Duration
	}{
		{'H', time.Hour},
		{'M', time.Minute},
		{'S', time.Second},
	}

	var total time.Duration
	digits := strings.Builder{}
	next := 0
	for index := range len(timePart) {
		char := timePart[index]
		if char >= '0' && char <= '9' || char == '.' {
			digits.WriteByte(char)
			continue
		}
		unit := next
		for unit < len(units) && units[unit].designator != char {
			unit++
		}
		if unit == len(units) || digits.Len() == 0 {
			return 0, ErrDuration
		}
		amount, err := strconv.ParseFloat(digits.String(), 64)
		if err != nil || amount < 0 {
			return 0, ErrDuration
		}
		total += time.Duration(amount * float64(units[unit].scale))
		digits.Reset()
		next = unit + 1
	}
	if digits.Len() != 0 {
		return 0, ErrDuration
	}
	return total, nil
}

// MarshalJSON renders the duration as a JSON string in ISO 8601 form.
func (d Duration) MarshalJSON() ([]byte, error) {
	return []byte(strconv.Quote(d.String())), nil
}

// UnmarshalJSON reads an ISO 8601 duration from a JSON string.
func (d *Duration) UnmarshalJSON(data []byte) error {
	text, err := strconv.Unquote(string(data))
	if err != nil {
		return ErrDuration
	}
	parsed, err := ParseDuration(text)
	if err != nil {
		return err
	}
	*d = parsed
	return nil
}
