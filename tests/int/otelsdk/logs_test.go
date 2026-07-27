package otelsdk_test

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
	"github.com/AtomiCloud/diene.go-otel/adapters/otelsdk"
	"github.com/AtomiCloud/diene.go-otel/lib/otel"
	"github.com/rs/zerolog"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

func TestLogLevelMappings(t *testing.T) {
	t.Parallel()

	tests := []struct {
		level    interfaces.LogLevel
		severity int
		zero     zerolog.Level
	}{
		{interfaces.LogLevelTrace, 1, zerolog.TraceLevel},
		{interfaces.LogLevelDebug, 5, zerolog.DebugLevel},
		{interfaces.LogLevelInfo, 9, zerolog.InfoLevel},
		{interfaces.LogLevelWarning, 13, zerolog.WarnLevel},
		{interfaces.LogLevelError, 17, zerolog.ErrorLevel},
		{interfaces.LogLevelFatal, 21, zerolog.FatalLevel},
	}
	for _, test := range tests {
		if !otelsdk.ValidLogLevel(test.level) {
			t.Errorf("valid level rejected: %q", test.level)
		}
		if got := otelsdk.LogSeverityFor(test.level); got != test.severity {
			t.Errorf("severity for %q: want %d, got %d", test.level, test.severity, got)
		}
		if got := otelsdk.ZerologLevel(test.level); got != test.zero {
			t.Errorf("zerolog level for %q: want %v, got %v", test.level, test.zero, got)
		}
	}
	if otelsdk.ValidLogLevel("unknown") || otelsdk.LogSeverityFor("unknown") != 0 ||
		otelsdk.ZerologLevel("unknown") != zerolog.NoLevel {
		t.Fatal("unknown level unexpectedly accepted")
	}
}

func TestTraceCorrelationAndLogAttributes(t *testing.T) {
	t.Parallel()

	var nilContext context.Context
	if len(otelsdk.TraceCorrelation(nilContext)) != 0 || len(otelsdk.TraceCorrelation(context.Background())) != 0 {
		t.Fatal("context without span must not correlate")
	}
	traceID := trace.TraceID{1, 2, 3}
	spanID := trace.SpanID{4, 5, 6}
	spanContext := trace.NewSpanContext(trace.SpanContextConfig{
		TraceID:    traceID,
		SpanID:     spanID,
		TraceFlags: trace.FlagsSampled,
	})
	ctx := trace.ContextWithSpanContext(context.Background(), spanContext)
	correlation := otelsdk.TraceCorrelation(ctx)
	if correlation[otelsdk.FieldTraceID] != traceID.String() ||
		correlation[otelsdk.FieldSpanID] != spanID.String() || correlation[otelsdk.FieldTraceFlags] != "01" {
		t.Fatalf("unexpected trace correlation %#v", correlation)
	}
	errorMessage := "boom"
	stackTrace := "stack"
	record := interfaces.NewLogRecord(time.Now(), interfaces.LogLevelError, "failed",
		map[string]any{"attempt": 2}, &errorMessage, &stackTrace)
	attributes := otelsdk.LogAttributesFor(record)
	want := map[string]string{"attempt": "2", otelsdk.FieldError: "boom", otelsdk.FieldStackTrace: "stack"}
	for _, keyValue := range attributes {
		if got, ok := want[string(keyValue.Key)]; !ok || fmt.Sprint(keyValue.Value.AsInterface()) != got {
			t.Errorf("unexpected log attribute %s=%v", keyValue.Key, keyValue.Value.AsInterface())
		}
	}
}

func TestLoggerSinkConsoleAndValidation(t *testing.T) {
	t.Parallel()

	buffer := &bytes.Buffer{}
	sink := otelsdk.NewLoggerSink(context.Background(), buffer,
		map[string]string{"service.name": "payments"}, true, otelsdk.LogExporter{}, nil, "payments")
	if !sink.Active() {
		t.Fatal("console sink must be active")
	}
	errorMessage := "boom"
	stackTrace := "stack"
	record := interfaces.NewLogRecord(
		time.Date(2026, 7, 25, 12, 0, 0, 0, time.UTC),
		interfaces.LogLevelError,
		"request failed",
		map[string]any{"attempt": 2},
		&errorMessage,
		&stackTrace,
	)
	traceID := trace.TraceID{1}
	spanID := trace.SpanID{2}
	ctx := trace.ContextWithSpanContext(context.Background(), trace.NewSpanContext(trace.SpanContextConfig{
		TraceID: traceID, SpanID: spanID, TraceFlags: trace.FlagsSampled,
	}))
	bound := sink.WithContext(ctx)
	var nilContext context.Context
	if bound == sink || sink.WithContext(nilContext) != sink {
		t.Fatal("context binding semantics changed")
	}
	if err := bound.Emit(record); err != nil {
		t.Fatalf("emit console log: %v", err)
	}
	var output map[string]any
	if err := json.Unmarshal(buffer.Bytes(), &output); err != nil {
		t.Fatalf("decode zerolog output %q: %v", buffer.String(), err)
	}
	for key, want := range map[string]any{
		"service.name":          "payments",
		"level":                 "error",
		"message":               "request failed",
		otelsdk.FieldTraceID:    traceID.String(),
		otelsdk.FieldSpanID:     spanID.String(),
		otelsdk.FieldTraceFlags: "01",
		otelsdk.FieldError:      "boom",
		otelsdk.FieldStackTrace: "stack",
	} {
		if output[key] != want {
			t.Errorf("console field %q: want %#v, got %#v", key, want, output[key])
		}
	}
	invalid := record
	invalid.Level = "unknown"
	assertProblemID(t, sink.EmitContext(nilContext, invalid), otel.FaultRecordInvalid)
	if err := otelsdk.ValidateLogRecord(invalid); err == nil {
		t.Fatal("adapter validation accepted invalid record")
	}

	inactive := otelsdk.NewLoggerSink(nilContext, nil, nil, false, otelsdk.LogExporter{}, nil, "scope")
	if inactive.Active() {
		t.Fatal("provider-free sink must be inactive")
	}
	if err := inactive.Emit(record); err != nil {
		t.Fatalf("inactive valid emit failed: %v", err)
	}
	if err := inactive.Flush(context.Background()); err != nil {
		t.Fatalf("inactive flush failed: %v", err)
	}
	if err := inactive.Shutdown(context.Background()); err != nil {
		t.Fatalf("inactive shutdown failed: %v", err)
	}
}

func TestRealLogsPipelineUsesOpaqueRecordingExporter(t *testing.T) {
	t.Parallel()

	exporter, capture := otelsdk.NewRecordingLogExporter()
	if !exporter.Defined() || (otelsdk.LogExporter{}).Defined() {
		t.Fatal("opaque exporter defined state mismatch")
	}
	resourceAttributes := map[string]string{"service.name": "payments"}
	sink := otelsdk.NewLoggerSink(context.Background(), nil, resourceAttributes, false,
		exporter, otelsdk.NewResource(resourceAttributes), "payments")
	if !sink.Active() {
		t.Fatal("recording pipeline must be active")
	}
	record := interfaces.NewLogRecord(
		time.Date(2026, 7, 25, 12, 0, 0, 0, time.UTC),
		interfaces.LogLevelInfo,
		"recorded",
		map[string]any{
			"bool":        true,
			"int":         int64(2),
			"float":       3.5,
			"string":      "value",
			"bool_slice":  []bool{true, false},
			"int_slice":   []int64{1, 2},
			"float_slice": []float64{1.5, 2.5},
			"text_slice":  []string{"one", "two"},
		},
		nil,
		nil,
	)
	if err := sink.Emit(record); err != nil {
		t.Fatalf("emit through real logs pipeline: %v", err)
	}
	if err := sink.Flush(context.Background()); err != nil {
		t.Fatalf("flush logs pipeline: %v", err)
	}
	records := capture.Records()
	if len(records) != 1 || records[0].Body != "recorded" ||
		records[0].Severity != otelsdk.LogSeverityFor(interfaces.LogLevelInfo) ||
		records[0].SeverityText != "info" || !records[0].Timestamp.Equal(record.Timestamp) {
		t.Fatalf("unexpected captured log %#v", records)
	}
	if len(records[0].Attributes) != len(record.Attributes) {
		t.Fatalf("attributes were not preserved: %#v", records[0].Attributes)
	}
	records[0].Attributes["bool"] = "mutated"
	if capture.Records()[0].Attributes["bool"] == "mutated" {
		t.Fatal("capture snapshot aliases internal state")
	}
	capture.Reset()
	if len(capture.Records()) != 0 {
		t.Fatal("capture reset failed")
	}
	if err := sink.Shutdown(context.Background()); err != nil {
		t.Fatalf("shutdown logs pipeline: %v", err)
	}
}

func TestLogExporterConstructorsAndFactory(t *testing.T) {
	t.Parallel()

	buffer := &bytes.Buffer{}
	console, err := otelsdk.NewConsoleLogExporter(buffer)
	if err != nil || !console.Defined() {
		t.Fatalf("console exporter: %v", err)
	}
	consoleDefault, err := otelsdk.NewConsoleLogExporter(nil)
	if err != nil || !consoleDefault.Defined() {
		t.Fatalf("default console exporter: %v", err)
	}
	settings := otel.OtlpSettings{}
	url := "https://collector.example:4318/v1/logs"
	timeout := time.Second
	settings.URL = &url
	settings.Headers = map[string]string{"authorization": "secret"}
	settings.Timeout = &timeout
	otlpExporter, err := otelsdk.NewOtlpLogExporter(context.Background(), settings)
	if err != nil || !otlpExporter.Defined() {
		t.Fatalf("OTLP logs exporter: %v", err)
	}
	if _, invalidErr := otelsdk.NewOtlpLogExporter(context.Background(), otel.OtlpSettings{
		URL: func() *string { invalid := "://"; return &invalid }(),
	}); invalidErr == nil {
		t.Fatal("invalid OTLP URL unexpectedly accepted")
	}
	for _, kind := range []otelsdk.ExporterKind{otelsdk.ExporterConsole, otelsdk.ExporterOtlp} {
		built, buildErr := otelsdk.DefaultLogExporterFactory(context.Background(), kind, settings)
		if buildErr != nil || !built.Defined() {
			t.Errorf("default log factory %q: %v", kind, buildErr)
		}
	}
	_, err = otelsdk.DefaultLogExporterFactory(context.Background(), "unknown", settings)
	assertProblemID(t, err, otel.FaultConfigInvalid)
	if err := otelsdk.UnknownExporterFault("unknown"); err == nil {
		t.Fatal("unknown exporter fault missing")
	}
	_ = consoleDefault
	_ = otlpExporter
}

func TestLogAttributeBridgeDefensiveValues(t *testing.T) {
	t.Parallel()

	values := []attribute.Value{
		attribute.BoolValue(true),
		attribute.Int64Value(1),
		attribute.Float64Value(1.5),
		attribute.StringValue("value"),
		attribute.BoolSliceValue([]bool{true}),
		attribute.Int64SliceValue([]int64{1}),
		attribute.Float64SliceValue([]float64{1.5}),
		attribute.StringSliceValue([]string{"value"}),
	}
	for _, value := range values {
		if got := otelsdk.LogAttributeValueString(value); got == "" {
			t.Errorf("attribute bridge lost %v", value)
		}
	}
	if got := otelsdk.LogAttributeValueString(attribute.Value{}); got != "" {
		t.Fatalf("unexpected empty value representation %q", got)
	}
	if got := otelsdk.LogAttributeValueString(attribute.Float64Value(math.Pi)); got == "" {
		t.Fatal("float bridge missing")
	}
}

func TestLoggerLifecycleFailuresAreProblemTyped(t *testing.T) {
	t.Parallel()

	exporter, _ := otelsdk.NewRecordingLogExporter()
	sink := otelsdk.NewLoggerSink(context.Background(), nil, nil, false, exporter, nil, "scope")
	cancelled, cancel := context.WithCancel(context.Background())
	cancel()
	flushErr := sink.Flush(cancelled)
	shutdownErr := sink.Shutdown(cancelled)
	if flushErr != nil {
		assertProblemID(t, flushErr, otel.FaultFlushFailed)
	}
	if shutdownErr != nil {
		assertProblemID(t, shutdownErr, otel.FaultShutdownFailed)
	}
	if flushErr == nil && shutdownErr == nil && !errors.Is(cancelled.Err(), context.Canceled) {
		t.Fatal("cancelled context invariant failed")
	}
}
