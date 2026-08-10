// Package otelsdk wires Diene's telemetry contract onto the OpenTelemetry Go SDK.
//
// It implements the logging and metrics seams owned by
// github.com/AtomiCloud/diene.go-interfaces and the trace seam owned by this
// module's lib/otel package, then exposes them through a single [Runtime] built
// from the canonical C0 §4 configuration block.
//
// Everything that touches the SDK lives here so lib/otel stays pure. Every
// exporter is constructed through an injectable factory, which is what lets the
// whole layer be proven without telemetry infrastructure: the integration suite
// injects in-memory exporters and never starts a collector.
//
// Signal posture follows the contract exactly. A signal whose pipeline is
// disabled, whose exporters are all off, or whose emission is owned by an
// injected seam builds NO provider at all: records still validate, so a consumer
// bug surfaces in every landscape, but nothing is exported. OTEL_SDK_DISABLED
// always wins over the block.
package otelsdk
