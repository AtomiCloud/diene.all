package coreutils

import (
	"strings"
	"time"

	_ "time/tzdata" // Embed timezone data so validation never reads host zoneinfo.
)

// IANATimeZoneRelease identifies the bundled IANA timezone release used by
// the C0 contract. Go's embedded tzdata is used rather than host zoneinfo.
const IANATimeZoneRelease = "2026b"

// IsIanaTimezone reports whether value is a valid, case-sensitive IANA zone.
// It accepts canonical identifiers and IANA aliases while rejecting host-local
// names, offsets, path traversal, and unknown abbreviations.
func IsIanaTimezone(value string) bool {
	if value == "" || value == "Local" || strings.Contains(value, "..") || strings.Contains(value, "\\") || strings.HasPrefix(value, "+") || strings.HasPrefix(value, "-") || value == "PST" {
		return false
	}
	_, errorValue := time.LoadLocation(value)
	return errorValue == nil
}
