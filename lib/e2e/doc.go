// Package e2e is the Go family's SIT and end-to-end test harness.
//
// It is a TEST harness, not a runtime library. It hosts nothing, serves
// nothing, and carries no Bruno orchestration: Bruno lives sample-side with the
// service templates, and a consumer running CLI-shaped message journeys needs
// none of it.
//
// # One journey, two drivers
//
// A system integration test wants to know that a service behaves the same
// whether it is exercised as a compiled artifact or wired up inside the test
// process. Those are different failure surfaces — the artifact proves the built
// binary, its flags, and its environment contract; the in-process run proves the
// same journey with a debugger attached and a stack trace on failure — so this
// package models both behind one [Driver] seam:
//
//   - [CompiledDriver] runs a built artifact through the
//     [interfaces.Terminal] seam owned by the family interfaces sibling.
//   - [InProcessDriver] runs an [Entrypoint] func in this process, capturing
//     the same stdout, stderr, and exit code.
//
// A [Journey] is a plain ordered list of [Step] values, so the SAME journey runs
// against both drivers and [CompareReports] proves the two agree. A journey that
// passes on one driver and fails on the other is the interesting result, and
// this is the only place the harness can see it.
//
// # Determinism seams
//
// Everything nondeterministic arrives by injection: process execution through
// [interfaces.Terminal], the filesystem through [interfaces.Vfs], and the clock
// and environment through [interfaces.System]. The published interfaces sibling
// ships in-memory implementations of all three, so a harness test never needs a
// real process, and [github.com/AtomiCloud/diene.go-e2e/adapters/process] binds
// the real one for the runs that do.
//
// # Failures
//
// Every failure is problem-typed (C0 §5) through [Problems], which mints RFC
// 9457 envelopes from the consuming service's own error portal. A step that
// fails its expectation is a value the caller can classify, not an opaque
// string.
package e2e
