package otel

import (
	"errors"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

// FaultVersion is the fixed problem type-URI version segment for this engine.
const FaultVersion = "v1"

// Fault identifiers minted by this module. Each id is a stable, single path
// segment of the RFC 9457 type URI built by [problem.TypeURI].
const (
	// FaultConfigInvalid reports a telemetry block that violates C0 §4.
	FaultConfigInvalid = "otel-config-invalid"
	// FaultEndpointInvalid reports an OTLP endpoint that is not an HTTP(S) URL on port 4318.
	FaultEndpointInvalid = "otel-endpoint-invalid"
	// FaultDurationInvalid reports a duration that is not a positive fixed-length ISO 8601 duration.
	FaultDurationInvalid = "otel-duration-invalid"
	// FaultSamplerInvalid reports an unsupported sampler type or out-of-range ratio.
	FaultSamplerInvalid = "otel-sampler-invalid"
	// FaultIdentityInvalid reports a service-tree identity with a blank coordinate.
	FaultIdentityInvalid = "otel-identity-invalid"
	// FaultRecordInvalid reports a telemetry record that cannot be emitted.
	FaultRecordInvalid = "otel-record-invalid"
	// FaultEmitFailed reports a failure while handing a record to the SDK.
	FaultEmitFailed = "otel-emit-failed"
	// FaultFlushFailed reports a failure while flushing a signal pipeline.
	FaultFlushFailed = "otel-flush-failed"
	// FaultShutdownFailed reports a failure while shutting a signal pipeline down.
	FaultShutdownFailed = "otel-shutdown-failed"
	// FaultEnvironmentUnavailable reports that the injected environment seam failed.
	FaultEnvironmentUnavailable = "otel-environment-unavailable"
)

// Fault status codes. Telemetry faults are server-side configuration or
// transport problems, so they carry 5xx except for caller-supplied input.
const (
	// FaultStatusInvalidInput is the status for caller-supplied invalid values.
	FaultStatusInvalidInput = 422
	// FaultStatusUnavailable is the status for engine and transport failures.
	FaultStatusUnavailable = 503
)

// Portal is the fixed LPSM portal this engine mints its type URIs from. It is a
// constant identity so type URIs are stable and never hand-authored per fault.
func Portal() problem.ErrorPortal {
	return problem.ErrorPortal{
		Scheme:    "https",
		Host:      "docs.diene.atomicloud.com",
		Landscape: "diene",
		Platform:  "go",
		Service:   "otel",
		Module:    "engine",
	}
}

// FaultProblem builds the RFC 9457 envelope for one engine fault. Its `type`
// URI is resolved through the single-source builder [problem.TypeURI] — never
// string concatenation. The portal and version are compile-time constants known
// to be valid, so the builder never fails here.
func FaultProblem(id, title, detail string, status int) problem.Problem {
	typeURI, _ := problem.TypeURI(Portal(), FaultVersion, id)
	occurrence := detail
	return problem.Problem{
		Type:   typeURI,
		Title:  title,
		Status: status,
		Detail: &occurrence,
		Data:   map[string]any{"id": id},
	}
}

// NewFault builds a problem-typed error from [FaultProblem].
func NewFault(id, title, detail string, status int) error {
	return problem.NewError(FaultProblem(id, title, detail, status))
}

// WrapFault builds a problem-typed error that also wraps cause, so errors.Is
// reaches the original failure while errors.As recovers the problem envelope.
func WrapFault(id, title, detail string, status int, cause error) error {
	return problem.WrapError(FaultProblem(id, title, detail, status), cause)
}

// NormalizeFault guarantees a non-nil error carries a [problem.Error]. An error
// already carrying one anywhere in its chain is returned unchanged; any other
// error is wrapped so errors.As recovers a [problem.Error] while errors.Is still
// reaches the original cause. A nil error stays nil.
func NormalizeFault(err error) error {
	if err == nil {
		return nil
	}
	var problemErr *problem.Error
	if errors.As(err, &problemErr) && problemErr != nil {
		return err
	}
	return problem.WrapError(problem.FromObject(err, problem.DefaultTransformOptions()), err)
}
