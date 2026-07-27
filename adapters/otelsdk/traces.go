package otelsdk

import (
	"context"

	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
	"github.com/AtomiCloud/diene.go-otel/lib/otel"
	"go.opentelemetry.io/otel/codes"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/trace"
	"go.opentelemetry.io/otel/trace/noop"
)

// NewSampler builds the sampler described by config.
//
// It returns nil when OTEL_TRACES_SAMPLER carries a value: the SDK reads that
// variable natively and an explicit sampler option would override the operator's
// escape hatch, so the correct action is to pass NO option.
func NewSampler(
	config otel.SamplerConfig,
	system interfaces.System,
) (sdktrace.Sampler, error) {
	var sampler sdktrace.Sampler
	switch config.Type {
	case otel.SamplerAlwaysOn:
		sampler = sdktrace.AlwaysSample()
	case otel.SamplerAlwaysOff:
		sampler = sdktrace.NeverSample()
	case otel.SamplerParentBasedTraceIDRatio:
		sampler = sdktrace.ParentBased(sdktrace.TraceIDRatioBased(config.Ratio))
	default:
		return nil, config.Validate()
	}
	if err := config.Validate(); err != nil {
		return nil, err
	}
	overridden, overrideErr := otel.EnvHasValue(system, otel.EnvTracesSampler)
	if overrideErr != nil {
		return nil, overrideErr
	}
	if overridden {
		return nil, nil
	}
	return sampler, nil
}

// TraceEmitter emits completed spans through the OpenTelemetry traces SDK.
//
// A record describes a finished span, so emission starts and immediately ends one
// span, attaching its attributes, events, and status. The span is always ended,
// including on a failure path, so a fault can never leak an unfinished span.
type TraceEmitter struct {
	tracer   trace.Tracer
	provider *sdktrace.TracerProvider
	active   bool
}

// NewTraceEmitter builds a trace emitter over tracer. A nil provider marks the
// emitter INACTIVE: records are still validated so consumer bugs surface in every
// landscape, but no span is created and nothing is exported.
func NewTraceEmitter(tracer trace.Tracer, provider *sdktrace.TracerProvider) *TraceEmitter {
	return &TraceEmitter{tracer: tracer, provider: provider, active: provider != nil}
}

// NewInactiveTraceEmitter builds a provider-free emitter backed by a local no-op
// tracer, which never consults any globally registered provider.
func NewInactiveTraceEmitter(scopeName string) *TraceEmitter {
	return NewTraceEmitter(noop.NewTracerProvider().Tracer(scopeName), nil)
}

// Active reports whether spans reach an exporter.
func (e *TraceEmitter) Active() bool { return e.active }

// Emit delivers record.
func (e *TraceEmitter) Emit(record otel.TraceRecord) error {
	return e.EmitContext(context.Background(), record)
}

// EmitContext delivers record as a child of ctx's active span, so an emitted span
// joins the surrounding trace instead of starting a new one.
func (e *TraceEmitter) EmitContext(ctx context.Context, record otel.TraceRecord) error {
	if err := record.Validate(); err != nil {
		return err
	}
	if !e.active {
		return nil
	}
	if ctx == nil {
		ctx = context.Background()
	}
	_, span := e.tracer.Start(ctx, record.Name,
		trace.WithTimestamp(record.Timestamp),
		trace.WithAttributes(Attributes(record.Attributes)...))
	defer span.End()
	for _, event := range record.Events {
		span.AddEvent(event.Name, trace.WithAttributes(Attributes(event.Attributes)...))
	}
	message := ""
	if record.StatusMessage != nil {
		message = *record.StatusMessage
	}
	span.SetStatus(SpanStatusCode(record.Status), message)
	return nil
}

// SpanStatusCode maps a portable trace status onto its OpenTelemetry status code.
func SpanStatusCode(status otel.TraceStatus) codes.Code {
	switch status {
	case otel.TraceStatusOK:
		return codes.Ok
	case otel.TraceStatusError:
		return codes.Error
	case otel.TraceStatusUnset:
		return codes.Unset
	}
	return codes.Unset
}

// Flush exports every buffered span.
func (e *TraceEmitter) Flush(ctx context.Context) error {
	if e.provider == nil {
		return nil
	}
	if err := e.provider.ForceFlush(ctx); err != nil {
		return otel.WrapFault(otel.FaultFlushFailed, "Telemetry flush failed",
			"the traces pipeline could not be flushed", otel.FaultStatusUnavailable, err)
	}
	return nil
}

// Shutdown stops the traces pipeline.
func (e *TraceEmitter) Shutdown(ctx context.Context) error {
	if e.provider == nil {
		return nil
	}
	if err := e.provider.Shutdown(ctx); err != nil {
		return otel.WrapFault(otel.FaultShutdownFailed, "Telemetry shutdown failed",
			"the traces pipeline could not be shut down", otel.FaultStatusUnavailable, err)
	}
	return nil
}
