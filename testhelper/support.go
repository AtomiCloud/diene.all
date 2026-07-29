package testhelper

import (
	"maps"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

// FixedNow returns the deterministic instant the fakes issue tokens at.
//
// It is a real, plausible date rather than the Unix epoch so a token's claims read
// sensibly in a failure message, and it is fixed so a suite that crosses an expiry
// boundary does so by advancing the clock rather than by sleeping.
func FixedNow() time.Time {
	return time.Date(2026, time.July, 25, 12, 0, 0, 0, time.UTC)
}

// SampleErrorPortal returns a realistic, valid error portal for tests, so fixtures
// never hand-format a problem type URI.
func SampleErrorPortal() problem.ErrorPortal {
	return problem.ErrorPortal{
		Scheme:    "https",
		Host:      "docs.raichu.cluster.atomi.cloud",
		Landscape: "lapras",
		Platform:  "alcohol",
		Service:   "zinc",
		Module:    "auth",
	}
}

// orDefault substitutes fallback for a blank value.
func orDefault(value string, fallback string) string {
	if value == "" {
		return fallback
	}
	return value
}

// toAny widens a string list for a JWT claim payload, which decodes as []any on the
// way back in.
func toAny(values []string) []any {
	widened := make([]any, 0, len(values))
	for _, value := range values {
		widened = append(widened, value)
	}
	return widened
}

// joinScopes renders a scope list in the space-delimited OAuth form.
func joinScopes(values []string) string {
	return strings.Join(values, " ")
}

// itoa renders an integer for a deterministic fake token value.
func itoa(value int) string {
	return strconv.Itoa(value)
}

// sortedKeys returns a map's keys in sorted order, so a fake's inspection helpers
// are deterministic.
func sortedKeys[Value any](entries map[string]Value) []string {
	return slices.Sorted(maps.Keys(entries))
}
