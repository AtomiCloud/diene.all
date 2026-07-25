package otel

import (
	"strconv"
	"strings"
	"time"

	"github.com/AtomiCloud/diene.go-core-utils/lib/coreutils"
)

// Fixed-length ISO 8601 duration component factors. Years and months are
// deliberately absent: their length depends on a calendar reference point, so
// they can never be converted to an exact machine duration.
const (
	hoursPerDay      = 24
	daysPerWeek      = 7
	secondsPerHour   = 3600
	secondsPerMinute = 60
	secondFactor     = float64(time.Second)
)

// ParseFixedDuration converts a C0 §1 ISO 8601 duration into an exact
// [time.Duration].
//
// The grammar is validated by [coreutils.ParseIsoDuration], so this engine never
// re-implements the wire format. Only FIXED-LENGTH designators are convertible:
// weeks, days, hours, minutes, and seconds. A duration carrying years or months
// is rejected because its exact length depends on a calendar reference point,
// and a non-positive duration is rejected because every C0 telemetry duration is
// a timeout or an export interval.
func ParseFixedDuration(value string) (time.Duration, error) {
	parsed, parseErr := coreutils.ParseIsoDuration(value)
	if parseErr != nil {
		return 0, WrapFault(FaultDurationInvalid, "Invalid telemetry duration",
			"expected a canonical ISO 8601 duration, got "+strconv.Quote(value), FaultStatusInvalidInput, parseErr)
	}
	date, timeOfDay, _ := strings.Cut(strings.TrimPrefix(parsed.String(), "P"), "T")
	if strings.ContainsAny(date, "YM") {
		return 0, WrapFault(FaultDurationInvalid, "Invalid telemetry duration",
			"expected a fixed-length ISO 8601 duration without years or months, got "+strconv.Quote(value),
			FaultStatusInvalidInput, nil)
	}
	// ParseIsoDuration already proves that the date half contains only these
	// designators (years/months were rejected above), so conversion cannot fail.
	seconds, _ := IsoComponentSeconds(date, map[byte]float64{
		'W': daysPerWeek * hoursPerDay * secondsPerHour,
		'D': hoursPerDay * secondsPerHour,
	}, value)
	// The same canonical parser proves the time half before conversion.
	timeSeconds, _ := IsoComponentSeconds(timeOfDay, map[byte]float64{
		'H': secondsPerHour,
		'M': secondsPerMinute,
		'S': 1,
	}, value)
	total := time.Duration((seconds + timeSeconds) * secondFactor)
	if total <= 0 {
		return 0, WrapFault(FaultDurationInvalid, "Invalid telemetry duration",
			"expected a positive ISO 8601 duration, got "+strconv.Quote(value), FaultStatusInvalidInput, nil)
	}
	return total, nil
}

// IsoComponentSeconds sums the seconds contributed by one half of an ISO 8601
// duration. Factors maps each designator this half accepts to its length in
// seconds; a designator outside that map is rejected so the caller's half-specific
// grammar stays authoritative. Source is the original value, quoted in faults.
func IsoComponentSeconds(section string, factors map[byte]float64, source string) (float64, error) {
	total := 0.0
	digits := strings.Builder{}
	for index := range len(section) {
		character := section[index]
		if (character >= '0' && character <= '9') || character == '.' {
			digits.WriteByte(character)
			continue
		}
		factor, known := factors[character]
		if !known || digits.Len() == 0 {
			return 0, WrapFault(FaultDurationInvalid, "Invalid telemetry duration",
				"unexpected ISO 8601 designator in "+strconv.Quote(source), FaultStatusInvalidInput, nil)
		}
		amount, amountErr := strconv.ParseFloat(digits.String(), 64)
		if amountErr != nil {
			return 0, WrapFault(FaultDurationInvalid, "Invalid telemetry duration",
				"unparsable ISO 8601 amount in "+strconv.Quote(source), FaultStatusInvalidInput, amountErr)
		}
		total += amount * factor
		digits.Reset()
	}
	if digits.Len() != 0 {
		return 0, WrapFault(FaultDurationInvalid, "Invalid telemetry duration",
			"trailing ISO 8601 amount without a designator in "+strconv.Quote(source), FaultStatusInvalidInput, nil)
	}
	return total, nil
}
