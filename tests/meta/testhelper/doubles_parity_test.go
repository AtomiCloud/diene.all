package testhelper_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
	"github.com/AtomiCloud/diene.go-otel/adapters/otelsdk"
	"github.com/AtomiCloud/diene.go-otel/lib/otel"
	"github.com/AtomiCloud/diene.go-otel/testhelper"
	sdkmetric "go.opentelemetry.io/otel/sdk/metric"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/sdk/trace/tracetest"
)

func TestInMemoryLoggerSinkOwnershipScriptingAndReset(t *testing.T) {
	t.Parallel()

	sink := testhelper.NewInMemoryLoggerSink()
	record := testhelper.SampleLogRecord()
	if err := sink.Emit(record); err != nil {
		t.Fatalf("emit log: %v", err)
	}
	snapshot := sink.Records()
	if len(snapshot) != 1 {
		t.Fatalf("expected one log, got %d", len(snapshot))
	}
	snapshot[0].Attributes["sample"] = false
	if sink.Records()[0].Attributes["sample"] != record.Attributes["sample"] {
		t.Fatal("log snapshot aliases stored record")
	}
	invalid := record.Clone()
	invalid.Level = "unknown"
	if err := sink.Emit(invalid); err == nil {
		t.Fatal("invalid log accepted")
	}

	sink.Reset()
	sentinel := errors.New("scripted log failure")
	sink.EnqueueResult(nil)
	sink.EnqueueResult(sentinel)
	if err := sink.Emit(record); err != nil {
		t.Fatalf("scripted nil result: %v", err)
	}
	if err := sink.Emit(record); !errors.Is(err, sentinel) {
		t.Fatalf("scripted failure mismatch: %v", err)
	}
	if err := sink.Emit(record); err != nil {
		t.Fatalf("post-script emit: %v", err)
	}
	if len(sink.Records()) != 1 {
		t.Fatal("scripted results were not consumed exactly once")
	}
	sink.Reset()
	if len(sink.Records()) != 0 {
		t.Fatal("log reset failed")
	}
}

func TestInMemoryMetricsCollectorOwnershipScriptingAndReset(t *testing.T) {
	t.Parallel()

	collector := testhelper.NewInMemoryMetricsCollector()
	record := testhelper.SampleMetricRecord()
	if err := collector.Emit(record); err != nil {
		t.Fatalf("emit metric: %v", err)
	}
	snapshot := collector.Records()
	if len(snapshot) != 1 {
		t.Fatalf("expected one metric, got %d", len(snapshot))
	}
	snapshot[0].Attributes["sample"] = false
	if collector.Records()[0].Attributes["sample"] != record.Attributes["sample"] {
		t.Fatal("metric snapshot aliases stored record")
	}
	invalid := record.Clone()
	invalid.Name = " "
	if err := collector.Emit(invalid); err == nil {
		t.Fatal("invalid metric accepted")
	}

	collector.Reset()
	sentinel := errors.New("scripted metric failure")
	collector.EnqueueResult(nil)
	collector.EnqueueResult(sentinel)
	if err := collector.Emit(record); err != nil {
		t.Fatalf("scripted nil result: %v", err)
	}
	if err := collector.Emit(record); !errors.Is(err, sentinel) {
		t.Fatalf("scripted failure mismatch: %v", err)
	}
	if err := collector.Emit(record); err != nil {
		t.Fatalf("post-script emit: %v", err)
	}
	if len(collector.Records()) != 1 {
		t.Fatal("scripted results were not consumed exactly once")
	}
	collector.Reset()
	if len(collector.Records()) != 0 {
		t.Fatal("metric reset failed")
	}
}

func TestInMemoryTraceEmitterOwnershipScriptingAndReset(t *testing.T) {
	t.Parallel()

	emitter := testhelper.NewInMemoryTraceEmitter()
	record := testhelper.SampleTraceRecord()
	invalid := record.Clone()
	invalid.Name = " "
	sentinel := errors.New("scripted trace failure")
	emitter.EnqueueResult(sentinel)
	if err := emitter.Emit(invalid); err == nil {
		t.Fatal("invalid trace accepted")
	}
	if err := emitter.Emit(record); !errors.Is(err, sentinel) {
		t.Fatalf("invalid trace consumed scripted result: %v", err)
	}
	emitter.EnqueueResult(nil)
	if err := emitter.Emit(record); err != nil {
		t.Fatalf("scripted nil trace result: %v", err)
	}
	if err := emitter.Emit(record); err != nil {
		t.Fatalf("normal trace emit: %v", err)
	}
	snapshot := emitter.Records()
	if len(snapshot) == 0 {
		t.Fatal("trace emitter recorded nothing")
	}
	snapshot[0].Attributes["sample"] = false
	if emitter.Records()[0].Attributes["sample"] != record.Attributes["sample"] {
		t.Fatal("trace snapshot aliases stored record")
	}
	emitter.Reset()
	if len(emitter.Records()) != 0 {
		t.Fatal("trace reset failed")
	}
}

func TestMockAndRealEmitSurfaceParity(t *testing.T) {
	t.Parallel()

	logExporter, logCapture := otelsdk.NewRecordingLogExporter()
	realLogs := otelsdk.NewLoggerSink(context.Background(), nil, nil, false, logExporter, nil, "parity")
	mockLogs := testhelper.NewInMemoryLoggerSink()
	validLog := testhelper.SampleLogRecord()
	invalidLog := validLog.Clone()
	invalidLog.Level = "unknown"
	assertEmitParity(t, realLogs.Emit, mockLogs.Emit, validLog, invalidLog)
	if len(logCapture.Records()) != 1 || len(mockLogs.Records()) != 1 {
		t.Fatal("log implementations did not accept exactly one valid record")
	}
	if err := realLogs.Shutdown(context.Background()); err != nil {
		t.Fatalf("shutdown real logs: %v", err)
	}

	reader := sdkmetric.NewManualReader()
	metricProvider := sdkmetric.NewMeterProvider(sdkmetric.WithReader(reader))
	realMetrics := otelsdk.NewMetricsCollector(metricProvider.Meter("parity"), metricProvider)
	mockMetrics := testhelper.NewInMemoryMetricsCollector()
	validMetric := testhelper.SampleMetricRecord()
	invalidMetric := validMetric.Clone()
	invalidMetric.Kind = interfaces.MetricKindCounter
	invalidMetric.Value = -1
	assertEmitParity(t, realMetrics.Emit, mockMetrics.Emit, validMetric, invalidMetric)
	if len(mockMetrics.Records()) != 1 {
		t.Fatal("metric mock did not accept exactly one valid record")
	}
	if err := realMetrics.Shutdown(context.Background()); err != nil {
		t.Fatalf("shutdown real metrics: %v", err)
	}

	spanExporter := tracetest.NewInMemoryExporter()
	traceProvider := sdktrace.NewTracerProvider(sdktrace.WithSyncer(spanExporter))
	realTraces := otelsdk.NewTraceEmitter(traceProvider.Tracer("parity"), traceProvider)
	mockTraces := testhelper.NewInMemoryTraceEmitter()
	validTrace := testhelper.SampleTraceRecord()
	invalidTrace := validTrace.Clone()
	invalidTrace.Status = "unknown"
	assertEmitParity(t, realTraces.Emit, mockTraces.Emit, validTrace, invalidTrace)
	if len(spanExporter.GetSpans()) != 1 || len(mockTraces.Records()) != 1 {
		t.Fatal("trace implementations did not accept exactly one valid record")
	}
	if err := realTraces.Shutdown(context.Background()); err != nil {
		t.Fatalf("shutdown real traces: %v", err)
	}
}

func assertEmitParity[Record any](
	t *testing.T,
	actual func(Record) error,
	mock func(Record) error,
	valid Record,
	invalid Record,
) {
	t.Helper()
	if realErr, mockErr := actual(valid), mock(valid); realErr != nil || mockErr != nil {
		t.Fatalf("valid verdict mismatch: real=%v mock=%v", realErr, mockErr)
	}
	realErr := actual(invalid)
	mockErr := mock(invalid)
	if realErr == nil || mockErr == nil {
		t.Fatalf("invalid verdict mismatch: real=%v mock=%v", realErr, mockErr)
	}
	if testhelper.FaultTypeURI(realErr) != testhelper.FaultTypeURI(mockErr) {
		t.Fatalf("problem type mismatch: real=%v mock=%v", realErr, mockErr)
	}
}

func TestDoublesImplementPublishedSeams(t *testing.T) {
	t.Parallel()

	var _ interfaces.LoggerSink = testhelper.NewInMemoryLoggerSink()
	var _ interfaces.MetricsCollector = testhelper.NewInMemoryMetricsCollector()
	var _ otel.TraceEmitter = testhelper.NewInMemoryTraceEmitter()
	if got, want := time.Now().UTC().Location(), time.UTC; got != want {
		t.Fatal("got != want")
	}
}
