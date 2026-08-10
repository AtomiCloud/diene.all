package coreutils

import "github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"

// NowWireInstant reads the current instant from the system clock seam and
// formats it as a canonical millisecond RFC 3339 UTC string. Routing every
// "now" through the C0 wire codec removes the ad hoc time formatting that
// produced the zinc_date defect class. The seam error is returned unwrapped so
// the caller keeps its problem typing.
func NowWireInstant(system interfaces.System) (string, error) {
	now, errorValue := system.NowUTC()
	if errorValue != nil {
		return "", errorValue
	}
	return FormatRFC3339UTC(now)
}
