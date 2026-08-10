package wire_test

import (
	"encoding/json"
	"fmt"
	"time"

	"github.com/AtomiCloud/diene.go-api-engine/lib/wire"
)

// A duration crosses the wire in ISO 8601 form, not as Go's integer nanosecond
// count, which no other language in the family reads.
func ExampleDuration() {
	timeout := wire.Duration(90 * time.Second)
	fmt.Println(timeout)
	fmt.Println(timeout.Std())

	encoded, err := json.Marshal(map[string]wire.Duration{"timeout": timeout})
	if err != nil {
		panic(err)
	}
	fmt.Println(string(encoded))
	// Output:
	// PT1M30S
	// 1m30s
	// {"timeout":"PT1M30S"}
}

func ExampleParseDuration() {
	for _, literal := range []string{"PT10S", "PT1H30M", "P1DT2H", "PT0.5S"} {
		parsed, err := wire.ParseDuration(literal)
		if err != nil {
			panic(err)
		}
		fmt.Printf("%s = %s\n", literal, parsed.Std())
	}

	// A year and a month have no fixed length, so C0 durations exclude them.
	if _, err := wire.ParseDuration("P1Y"); err != nil {
		fmt.Println("P1Y rejected")
	}
	// Output:
	// PT10S = 10s
	// PT1H30M = 1h30m0s
	// P1DT2H = 26h0m0s
	// PT0.5S = 500ms
	// P1Y rejected
}

// An instant always renders as an RFC 3339 UTC timestamp, whatever offset it
// was built or parsed from — which is what makes it comparable across services.
func ExampleInstant() {
	singapore, err := time.LoadLocation("Asia/Singapore")
	if err != nil {
		panic(err)
	}
	local := time.Date(2026, 7, 26, 3, 35, 0, 0, singapore)

	fmt.Println(wire.NewInstant(local))

	parsed, err := wire.ParseInstant("2026-07-26T03:35:00+08:00")
	if err != nil {
		panic(err)
	}
	fmt.Println(parsed)
	// Output:
	// 2026-07-25T19:35:00Z
	// 2026-07-25T19:35:00Z
}

// A timezone is an IANA identifier. An offset or an abbreviation is rejected:
// neither can be resolved back to the political rules a future timestamp has to
// be interpreted under.
func ExampleParseZone() {
	zone, err := wire.ParseZone("Asia/Singapore")
	if err != nil {
		panic(err)
	}
	fmt.Println(zone)

	for _, rejected := range []string{"+08:00", "SGT", "Local"} {
		if _, err := wire.ParseZone(rejected); err != nil {
			fmt.Printf("%s rejected\n", rejected)
		}
	}
	// Output:
	// Asia/Singapore
	// +08:00 rejected
	// SGT rejected
	// Local rejected
}
