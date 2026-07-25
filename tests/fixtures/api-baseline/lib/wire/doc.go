// Package wire implements the C0 §1 serialization contract for the values this
// engine puts on, or reads off, the network.
//
// C0 fixes one wire vocabulary across every AtomiCloud language so a value
// written by one service is read identically by the next: a datetime is an
// RFC 3339 UTC instant, a duration is an ISO 8601 duration, and a timezone is
// an IANA identifier — never a UTC offset and never an abbreviation, because
// both lose the political history a zone id carries.
//
// The types here exist because Go's own defaults disagree with that contract:
// [time.Duration] marshals to an integer nanosecond count, and [time.Time]
// marshals in whatever offset it happens to carry. [Duration], [Instant], and
// [Zone] are the contract-shaped replacements, and every one of them
// round-trips: parsing a rendered value returns the value it was rendered
// from.
//
// The concrete shapes and samples this package is validated against live in
// tests/fixtures/c0/wire.json, so a C0-published fixture can replace them
// without touching test code.
package wire
