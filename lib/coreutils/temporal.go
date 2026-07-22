package coreutils

import "strings"

// C0TemporalProvenance records the source and reproducibility pins for C0 vectors.
type C0TemporalProvenance struct {
	// ContractVersion is the monotonic C0 vector version.
	ContractVersion string
	// C0Section identifies the binding C0 contract section.
	C0Section string
	// C0Source identifies the repository contract source.
	C0Source string
	// IANARelease identifies the required IANA timezone release.
	IANARelease string
	// IANAArchiveURL is the official source archive URL.
	IANAArchiveURL string
	// IANAArchiveSHA256 is the official archive digest.
	IANAArchiveSHA256 string
}

// C0Cases contains positive and negative wire cases.
type C0Cases struct {
	// Valid contains values that must round-trip.
	Valid []string
	// Invalid contains values that must be rejected.
	Invalid []string
}

// C0InstantVector fixes an input instant and canonical UTC output.
type C0InstantVector struct {
	// Input is an RFC 3339 value, potentially with an offset.
	Input string
	// CanonicalUTC is its RFC 3339 UTC Z representation.
	CanonicalUTC string
}

// C0TemporalContract is the shared, deterministic C0 temporal contract.
type C0TemporalContract struct {
	// Provenance pins the contract inputs.
	Provenance C0TemporalProvenance
	// Dates contains calendar-date cases.
	Dates C0Cases
	// Times contains wall-clock cases.
	Times C0Cases
	// Durations contains ISO duration cases.
	Durations C0Cases
	// Timezones contains IANA timezone cases.
	Timezones C0Cases
	// Instants contains normalization vectors.
	Instants []C0InstantVector
	// InvalidInstants contains strict-parser rejection cases.
	InvalidInstants []string
}

// DigestPayload deterministically serializes the temporal vectors for stale-fixture detection.
func (contract C0TemporalContract) DigestPayload() string {
	instantValues := make([]string, len(contract.Instants))
	for index, value := range contract.Instants {
		instantValues[index] = value.Input + ">" + value.CanonicalUTC
	}
	return strings.Join([]string{
		"contract=" + contract.Provenance.ContractVersion,
		"c0=" + contract.Provenance.C0Section + "|" + contract.Provenance.C0Source,
		"iana=" + contract.Provenance.IANARelease + "|" + contract.Provenance.IANAArchiveSHA256,
		"dates.valid=" + strings.Join(contract.Dates.Valid, ","),
		"dates.invalid=" + strings.Join(contract.Dates.Invalid, ","),
		"times.valid=" + strings.Join(contract.Times.Valid, ","),
		"times.invalid=" + strings.Join(contract.Times.Invalid, ","),
		"durations.valid=" + strings.Join(contract.Durations.Valid, ","),
		"durations.invalid=" + strings.Join(contract.Durations.Invalid, ","),
		"timezones.valid=" + strings.Join(contract.Timezones.Valid, ","),
		"timezones.invalid=" + strings.Join(contract.Timezones.Invalid, ","),
		"instants=" + strings.Join(instantValues, ","),
		"invalidInstants=" + strings.Join(contract.InvalidInstants, ","),
	}, "\n") + "\n"
}

// C0Temporal is the single, version-pinned temporal contract for Go consumers.
var C0Temporal = C0TemporalContract{
	Provenance:      C0TemporalProvenance{ContractVersion: "1", C0Section: "C0 §1 Serialization", C0Source: "goals/c0-contracts.md", IANARelease: IANATimeZoneRelease, IANAArchiveURL: "https://data.iana.org/time-zones/releases/tzdata2026b.tar.gz", IANAArchiveSHA256: "114543d9f19a6bfeb5bca43686aea173d38755a3db1f2eec112647ae92c6f544"},
	Dates:           C0Cases{Valid: []string{"2026-07-21", "2000-02-29", "0001-01-01", "9999-12-31"}, Invalid: []string{"21-07-2026", "2026-02-30", "2026-13-01", "2026-7-1", "2026/07/21"}},
	Times:           C0Cases{Valid: []string{"00:00:00", "01:02:03", "23:59:59"}, Invalid: []string{"24:00:00", "01:60:00", "01:02:60", "1:02:03", "01:02"}},
	Durations:       C0Cases{Valid: []string{"P1DT2H3M4.5S", "PT0.5S", "P1Y2M3DT4H5M6S", "P1W"}, Invalid: []string{"10 minutes", "P", "PT", "1DT2H", "P1H"}},
	Timezones:       C0Cases{Valid: []string{"Asia/Singapore", "America/Argentina/Buenos_Aires", "Etc/UTC", "UTC", "US/Eastern", "EST", "GMT"}, Invalid: []string{"Area/NotAnIanaZone", "+08:00", "asia/singapore", "Area/../Location", "PST", ""}},
	Instants:        []C0InstantVector{{Input: "2026-07-21T09:02:03+08:00", CanonicalUTC: "2026-07-21T01:02:03.000Z"}, {Input: "2026-07-21T01:02:03Z", CanonicalUTC: "2026-07-21T01:02:03.000Z"}, {Input: "2026-07-21T01:02:03.456Z", CanonicalUTC: "2026-07-21T01:02:03.456Z"}},
	InvalidInstants: []string{"2026-07-21T01:02:03+00:00", "2026-07-21T01:02:03+08:00", "2026-07-21T01:02:03", "2026-02-30T01:02:03Z", "2026-07-21 01:02:03Z"},
}
