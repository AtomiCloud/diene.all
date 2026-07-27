package tracing_test

import (
	"errors"
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-consumer/adapters/tracing"
	interfaceshelper "github.com/AtomiCloud/diene.go-interfaces/testhelper"
	"github.com/AtomiCloud/diene.go-otel/lib/otel"
	otelhelper "github.com/AtomiCloud/diene.go-otel/testhelper"
)

func TestTracerRecordsSuccessAndFailure(t *testing.T) {
	t.Parallel()
	system := interfaceshelper.NewInMemorySystem(interfaceshelper.InMemorySystemOptions{})
	emitter := otelhelper.NewInMemoryTraceEmitter()
	tracer, constructErr := tracing.New(system, emitter)
	if constructErr != nil {
		t.Fatalf("construct tracer: %v", constructErr)
	}

	span, startErr := tracer.Start("adapter.success", map[string]any{"component": "test"})
	if startErr != nil {
		t.Fatalf("start success span: %v", startErr)
	}
	if err := span.End(nil); err != nil {
		t.Fatalf("end success span: %v", err)
	}

	operationErr := errors.New("operation failed")
	span, startErr = tracer.Start("adapter.failure", nil)
	if startErr != nil {
		t.Fatalf("start failure span: %v", startErr)
	}
	if err := span.End(operationErr); !errors.Is(err, operationErr) {
		t.Fatalf("expected operation error, got %v", err)
	}

	records := emitter.Records()
	if len(records) != 2 {
		t.Fatalf("expected two trace records, got %d", len(records))
	}
	if records[0].Status != otel.TraceStatusOK || records[0].Attributes["component"] != "test" {
		t.Fatalf("unexpected success record: %#v", records[0])
	}
	if records[1].Status != otel.TraceStatusError || records[1].StatusMessage == nil || *records[1].StatusMessage != operationErr.Error() {
		t.Fatalf("unexpected failure record: %#v", records[1])
	}
}

func TestTracerPreservesOperationAndTelemetryFailures(t *testing.T) {
	t.Parallel()
	system := interfaceshelper.NewInMemorySystem(interfaceshelper.InMemorySystemOptions{})
	emitter := otelhelper.NewInMemoryTraceEmitter()
	tracer, constructErr := tracing.New(system, emitter)
	if constructErr != nil {
		t.Fatalf("construct tracer: %v", constructErr)
	}

	emitErr := errors.New("emit failed")
	emitter.EnqueueResult(emitErr)
	span, startErr := tracer.Start("adapter.emit_failure", nil)
	if startErr != nil {
		t.Fatalf("start span: %v", startErr)
	}
	if err := span.End(nil); !errors.Is(err, emitErr) {
		t.Fatalf("expected telemetry error, got %v", err)
	}

	operationErr := errors.New("operation failed")
	emitter.EnqueueResult(emitErr)
	span, startErr = tracer.Start("adapter.joined_failure", nil)
	if startErr != nil {
		t.Fatalf("start joined span: %v", startErr)
	}
	joined := span.End(operationErr)
	if !errors.Is(joined, operationErr) || !errors.Is(joined, emitErr) {
		t.Fatalf("expected joined operation and telemetry failures, got %v", joined)
	}
}

func TestTracerRejectsMissingSeamsAndClockFailure(t *testing.T) {
	t.Parallel()
	system := interfaceshelper.NewInMemorySystem(interfaceshelper.InMemorySystemOptions{})
	emitter := otelhelper.NewInMemoryTraceEmitter()
	if _, err := tracing.New(nil, emitter); err == nil {
		t.Fatal("expected missing system failure")
	}
	if _, err := tracing.New(system, nil); err == nil {
		t.Fatal("expected missing emitter failure")
	}

	clockErr := errors.New("clock failed")
	system.EnqueueClockResult(systemNow(t, system), clockErr)
	tracer, err := tracing.New(system, emitter)
	if err != nil {
		t.Fatalf("construct tracer: %v", err)
	}
	if _, err := tracer.Start("adapter.clock_failure", nil); !errors.Is(err, clockErr) {
		t.Fatalf("expected clock failure, got %v", err)
	}
}

func systemNow(t *testing.T, system *interfaceshelper.InMemorySystem) time.Time {
	t.Helper()
	now, err := system.NowUTC()
	if err != nil {
		t.Fatalf("read system clock: %v", err)
	}
	return now
}
