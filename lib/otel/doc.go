// Package otel provides Diene's OpenTelemetry engine.
//
// This package owns the pure contract layer: the canonical C0 §4 telemetry
// configuration block, its exported JSON Schema, the service-tree to semantic
// convention resource mapping, the OTEL_* environment precedence rules, and the
// trace emission seam. It constructs no SDK object and performs no I/O, so every
// rule here is directly testable without telemetry infrastructure.
//
// The logging and metrics emission seams are owned by
// github.com/AtomiCloud/diene.go-interfaces and implemented in this module's
// adapters/otelsdk package. The trace seam ([TraceEmitter]) is owned here
// because trace test seams are language-local: no cross-language shape parity is
// required, so each language family defines its own idiomatic tracer interface,
// mock, and TestHelper.
//
// Every non-nil error returned by this package carries a *problem.Error from
// github.com/AtomiCloud/diene.go-errors-problems, so callers recover structured
// RFC 9457 details with errors.As while errors.Is still reaches the cause.
package otel
