package otelsdk_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-otel/adapters/otelsdk"
	"github.com/AtomiCloud/diene.go-otel/lib/otel"
	"go.opentelemetry.io/otel/codes"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/sdk/trace/tracetest"
)

func TestSamplerConstructionAndOverride(t *testing.T) {
	t.Parallel()

	tests := []otel.SamplerConfig{
		{Type: otel.SamplerAlwaysOn, Ratio: 1},
		{Type: otel.SamplerAlwaysOff, Ratio: 1},
		{Type: otel.SamplerParentBasedTraceIDRatio, Ratio: 0.5},
	}
	for _, config := range tests {
		sampler, err := otelsdk.NewSampler(config, systemWith(nil))
		if err != nil || sampler == nil || sampler.Description() == "" {
			t.Errorf("sampler %q: %#v, %v", config.Type, sampler, err)
		}
	}
	overridden, err := otelsdk.NewSampler(tests[0], systemWith(map[string]string{
		otel.EnvTracesSampler: "always_off",
	}))
	if err != nil || overridden != nil {
		t.Fatalf("env sampler must defer: %#v, %v", overridden, err)
	}
	_, err = otelsdk.NewSampler(otel.SamplerConfig{Type: "unknown", Ratio: 1}, systemWith(nil))
	assertProblemID(t, err, otel.FaultSamplerInvalid)
	_, err = otelsdk.NewSampler(otel.SamplerConfig{Type: otel.SamplerAlwaysOn, Ratio: -1}, systemWith(nil))
	assertProblemID(t, err, otel.FaultSamplerInvalid)
	_, err = otelsdk.NewSampler(tests[0], nil)
	assertProblemID(t, err, otel.FaultEnvironmentUnavailable)
}

func TestTraceEmitterExportsCompletedSpan(t *testing.T) {
	t.Parallel()

	exporter := tracetest.NewInMemoryExporter()
	provider := sdktrace.NewTracerProvider(sdktrace.WithSyncer(exporter))
	emitter := otelsdk.NewTraceEmitter(provider.Tracer("trace-test"), provider)
	if !emitter.Active() {
		t.Fatal("provider-backed emitter must be active")
	}
	message := "failed"
	record := otel.NewTraceRecord(
		time.Date(2026, 7, 25, 12, 0, 0, 0, time.UTC),
		"operation",
		map[string]any{"attempt": 2},
		[]otel.TraceEvent{otel.NewTraceEvent("retry", map[string]any{"index": 1})},
		otel.TraceStatusError,
		&message,
	)
	if err := emitter.Emit(record); err != nil {
		t.Fatalf("emit span: %v", err)
	}
	if err := emitter.Flush(context.Background()); err != nil {
		t.Fatalf("flush spans: %v", err)
	}
	spans := exporter.GetSpans()
	if len(spans) != 1 || spans[0].Name != "operation" || spans[0].Status.Code != codes.Error ||
		spans[0].Status.Description != "failed" || len(spans[0].Events) != 1 ||
		spans[0].Events[0].Name != "retry" || !spans[0].StartTime.Equal(record.Timestamp) {
		t.Fatalf("unexpected exported span %#v", spans)
	}
	if len(spans[0].Attributes) != 1 || string(spans[0].Attributes[0].Key) != "attempt" {
		t.Fatalf("span attributes missing: %#v", spans[0].Attributes)
	}
	exporter.Reset()
	withoutMessage := record.Clone()
	withoutMessage.Status = otel.TraceStatusUnset
	withoutMessage.StatusMessage = nil
	var nilContext context.Context
	if err := emitter.EmitContext(nilContext, withoutMessage); err != nil {
		t.Fatalf("emit span without status message: %v", err)
	}
	if err := emitter.Shutdown(context.Background()); err != nil {
		t.Fatalf("shutdown traces: %v", err)
	}
}

func TestInactiveTraceEmitterStillValidates(t *testing.T) {
	t.Parallel()

	emitter := otelsdk.NewInactiveTraceEmitter("inactive")
	if emitter.Active() {
		t.Fatal("inactive emitter marked active")
	}
	record := otel.NewTraceRecord(time.Now(), "operation", nil, nil, otel.TraceStatusOK, nil)
	if err := emitter.Emit(record); err != nil {
		t.Fatalf("inactive valid emit: %v", err)
	}
	invalid := record.Clone()
	invalid.Name = " "
	assertProblemID(t, emitter.Emit(invalid), otel.FaultRecordInvalid)
	if err := emitter.Flush(context.Background()); err != nil {
		t.Fatalf("inactive flush: %v", err)
	}
	if err := emitter.Shutdown(context.Background()); err != nil {
		t.Fatalf("inactive shutdown: %v", err)
	}
}

func TestTraceStatusMapping(t *testing.T) {
	t.Parallel()

	tests := map[otel.TraceStatus]codes.Code{
		otel.TraceStatusUnset: codes.Unset,
		otel.TraceStatusOK:    codes.Ok,
		otel.TraceStatusError: codes.Error,
		"unknown":             codes.Unset,
	}
	for status, want := range tests {
		if got := otelsdk.SpanStatusCode(status); got != want {
			t.Errorf("status %q: want %v, got %v", status, want, got)
		}
	}
}

func TestTraceLifecycleFailuresAreProblemTyped(t *testing.T) {
	t.Parallel()

	flushCause := errors.New("flush failed")
	processor := &lifecycleSpanProcessor{forceFlushErr: flushCause}
	provider := sdktrace.NewTracerProvider(sdktrace.WithSpanProcessor(processor))
	emitter := otelsdk.NewTraceEmitter(provider.Tracer("flush"), provider)
	err := emitter.Flush(context.Background())
	assertProblemID(t, err, otel.FaultFlushFailed)
	if !errors.Is(err, flushCause) {
		t.Fatalf("flush cause lost: %v", err)
	}
	_ = emitter.Shutdown(context.Background())

	shutdownCause := errors.New("shutdown failed")
	processor = &lifecycleSpanProcessor{shutdownErr: shutdownCause}
	provider = sdktrace.NewTracerProvider(sdktrace.WithSpanProcessor(processor))
	emitter = otelsdk.NewTraceEmitter(provider.Tracer("shutdown"), provider)
	err = emitter.Shutdown(context.Background())
	assertProblemID(t, err, otel.FaultShutdownFailed)
	if !errors.Is(err, shutdownCause) {
		t.Fatalf("shutdown cause lost: %v", err)
	}
}
