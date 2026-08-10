package otelsdk_test

import (
	"bytes"
	"context"
	"errors"
	"os"
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-otel/adapters/otelsdk"
	"github.com/AtomiCloud/diene.go-otel/lib/otel"
	"github.com/AtomiCloud/diene.go-otel/testhelper"
)

func TestResolveOptions(t *testing.T) {
	t.Parallel()

	defaults := otelsdk.DefaultOptions()
	if defaults.System == nil || defaults.LogWriter == nil || defaults.SpanExporters == nil ||
		defaults.MetricExporters == nil || defaults.LogExporters == nil ||
		defaults.GlobalRegistration || defaults.Context == nil {
		t.Fatalf("unexpected defaults %#v", defaults)
	}
	system := systemWith(nil)
	writer := &bytes.Buffer{}
	logs := testhelper.NewInMemoryLoggerSink()
	metrics := testhelper.NewInMemoryMetricsCollector()
	traces := testhelper.NewInMemoryTraceEmitter()
	spanFactory := otelsdk.DefaultSpanExporterFactory
	metricFactory := otelsdk.DefaultMetricExporterFactory
	logFactory := otelsdk.DefaultLogExporterFactory
	options, err := otelsdk.ResolveOptions(
		nil,
		otelsdk.WithSystem(system),
		otelsdk.WithLogWriter(writer),
		otelsdk.WithLoggerSink(logs),
		otelsdk.WithMetricsCollector(metrics),
		otelsdk.WithTraceEmitter(traces),
		otelsdk.WithSpanExporterFactory(spanFactory),
		otelsdk.WithMetricExporterFactory(metricFactory),
		otelsdk.WithLogExporterFactory(logFactory),
		otelsdk.WithGlobalRegistration(true),
	)
	if err != nil {
		t.Fatalf("resolve options: %v", err)
	}
	if options.System != system || options.LogWriter != writer || options.LoggerSink != logs ||
		options.MetricsCollector != metrics || options.TraceEmitter != traces || !options.GlobalRegistration {
		t.Fatalf("options were not applied: %#v", options)
	}
	if got := otelsdk.ExporterConsole.String(); got != "console" {
		t.Fatalf("unexpected exporter string %q", got)
	}

	invalidOptions := []otelsdk.Option{
		otelsdk.WithSystem(nil),
		otelsdk.WithLogWriter(nil),
		otelsdk.WithSpanExporterFactory(nil),
		otelsdk.WithMetricExporterFactory(nil),
		otelsdk.WithLogExporterFactory(nil),
	}
	for _, option := range invalidOptions {
		_, resolveErr := otelsdk.ResolveOptions(option)
		if resolveErr == nil {
			t.Fatal("invalid option unexpectedly accepted")
		}
	}
	cleared, err := otelsdk.ResolveOptions(
		otelsdk.WithLoggerSink(nil),
		otelsdk.WithMetricsCollector(nil),
		otelsdk.WithTraceEmitter(nil),
	)
	if err != nil || cleared.LoggerSink != nil || cleared.MetricsCollector != nil || cleared.TraceEmitter != nil {
		t.Fatalf("nil seams must mean no injection: %#v, %v", cleared, err)
	}
}

func TestProcessSystem(t *testing.T) {
	system := otelsdk.NewSystem()
	t.Setenv("DIENE_OTEL_TEST", "value")
	value, err := system.Environment("DIENE_OTEL_TEST")
	if err != nil || value == nil || *value != "value" {
		t.Fatalf("environment lookup failed: %v, %v", value, err)
	}
	if unset, unsetErr := system.Environment("DIENE_OTEL_UNSET"); unsetErr != nil || unset != nil {
		t.Fatalf("unset environment mismatch: %v, %v", unset, unsetErr)
	}
	directory, err := system.CurrentDirectory()
	if err != nil || directory == "" {
		t.Fatalf("current directory failed: %q, %v", directory, err)
	}
	now, err := system.NowUTC()
	if err != nil || now.Location() != time.UTC {
		t.Fatalf("UTC clock failed: %v, %v", now, err)
	}
	if err := system.Delay(context.Background(), time.Millisecond); err != nil {
		t.Fatalf("positive delay failed: %v", err)
	}
	if err := system.Delay(context.Background(), 0); err != nil {
		t.Fatalf("zero delay with live context should return nil, got %v", err)
	}
	cancelled, cancel := context.WithCancel(context.Background())
	cancel()
	if err := system.Delay(cancelled, time.Hour); !errors.Is(err, context.Canceled) {
		t.Fatalf("cancelled delay mismatch: %v", err)
	}

	original, statErr := os.Stat(directory)
	if statErr != nil || !original.IsDir() {
		t.Fatalf("reported directory is not usable: %v", statErr)
	}
}

func TestProcessSystemCurrentDirectoryFailureIsProblemTyped(t *testing.T) {
	temporary := t.TempDir()
	t.Chdir(temporary)
	if err := os.Remove(temporary); err != nil {
		t.Fatalf("remove current temporary directory: %v", err)
	}
	_, directoryErr := otelsdk.NewSystem().CurrentDirectory()
	assertProblemID(t, directoryErr, otel.FaultEnvironmentUnavailable)
}
