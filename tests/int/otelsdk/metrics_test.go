package otelsdk_test

import (
	"context"
	"errors"
	"math"
	"slices"
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
	"github.com/AtomiCloud/diene.go-otel/adapters/otelsdk"
	"github.com/AtomiCloud/diene.go-otel/lib/otel"
	sdkmetric "go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/metric/metricdata"
)

func TestInstrumentCacheCreatesAndReusesInstruments(t *testing.T) {
	t.Parallel()

	provider := sdkmetric.NewMeterProvider()
	t.Cleanup(func() {
		if err := provider.Shutdown(context.Background()); err != nil {
			t.Errorf("shutdown meter provider: %v", err)
		}
	})
	cache := otelsdk.NewInstrumentCache(provider.Meter("test"))
	counter, err := cache.Counter("requests", "1")
	if err != nil {
		t.Fatalf("create counter: %v", err)
	}
	cachedCounter, err := cache.Counter("requests", "1")
	if err != nil || counter != cachedCounter {
		t.Fatalf("counter cache miss: %v", err)
	}
	gauge, err := cache.Gauge("queue.depth", "1")
	if err != nil {
		t.Fatalf("create gauge: %v", err)
	}
	cachedGauge, err := cache.Gauge("queue.depth", "1")
	if err != nil || gauge != cachedGauge {
		t.Fatalf("gauge cache miss: %v", err)
	}
	histogram, err := cache.Histogram("request.duration", "ms")
	if err != nil {
		t.Fatalf("create histogram: %v", err)
	}
	cachedHistogram, err := cache.Histogram("request.duration", "ms")
	if err != nil || histogram != cachedHistogram {
		t.Fatalf("histogram cache miss: %v", err)
	}

	for _, create := range []func() error{
		func() error { _, createErr := cache.Counter("bad name", ""); return createErr },
		func() error { _, createErr := cache.Gauge("bad name", ""); return createErr },
		func() error { _, createErr := cache.Histogram("bad name", ""); return createErr },
	} {
		assertProblemID(t, create(), otel.FaultEmitFailed)
	}
}

func TestMetricsCollectorRecordsAllKinds(t *testing.T) {
	t.Parallel()

	reader := sdkmetric.NewManualReader()
	provider := sdkmetric.NewMeterProvider(sdkmetric.WithReader(reader))
	collector := otelsdk.NewMetricsCollector(provider.Meter("metrics-test"), provider)
	if !collector.Active() {
		t.Fatal("collector with provider must be active")
	}
	unit := "ms"
	records := []interfaces.MetricRecord{
		interfaces.NewMetricRecord(time.Now(), "requests", interfaces.MetricKindCounter, 2, nil,
			map[string]any{"route": "/"}),
		interfaces.NewMetricRecord(time.Now(), "queue.depth", interfaces.MetricKindGauge, 3, nil,
			map[string]any{"queue": "default"}),
		interfaces.NewMetricRecord(time.Now(), "request.duration", interfaces.MetricKindHistogram, 4.5, &unit,
			map[string]any{"route": "/"}),
	}
	for _, record := range records {
		if err := collector.Emit(record); err != nil {
			t.Fatalf("emit %q: %v", record.Name, err)
		}
	}
	for _, kind := range []interfaces.MetricKind{
		interfaces.MetricKindCounter,
		interfaces.MetricKindGauge,
		interfaces.MetricKindHistogram,
	} {
		invalidName := interfaces.NewMetricRecord(time.Now(), "bad name", kind, 1, nil, nil)
		assertProblemID(t, collector.Emit(invalidName), otel.FaultEmitFailed)
	}
	var collected metricdata.ResourceMetrics
	if err := reader.Collect(context.Background(), &collected); err != nil {
		t.Fatalf("collect metrics: %v", err)
	}
	names := []string{}
	for _, scope := range collected.ScopeMetrics {
		for _, metric := range scope.Metrics {
			names = append(names, metric.Name)
			switch metric.Name {
			case "requests":
				if _, ok := metric.Data.(metricdata.Sum[float64]); !ok {
					t.Errorf("counter data has type %T", metric.Data)
				}
			case "queue.depth":
				if _, ok := metric.Data.(metricdata.Gauge[float64]); !ok {
					t.Errorf("gauge data has type %T", metric.Data)
				}
			case "request.duration":
				if _, ok := metric.Data.(metricdata.Histogram[float64]); !ok || metric.Unit != "ms" {
					t.Errorf("histogram data/unit mismatch: %T %q", metric.Data, metric.Unit)
				}
			default:
				t.Errorf("unexpected metric %q", metric.Name)
			}
		}
	}
	for _, name := range []string{"requests", "queue.depth", "request.duration"} {
		if !slices.Contains(names, name) {
			t.Errorf("metric %q was not collected: %#v", name, names)
		}
	}
	if err := collector.Flush(context.Background()); err != nil {
		t.Fatalf("flush metrics: %v", err)
	}
	if err := collector.Shutdown(context.Background()); err != nil {
		t.Fatalf("shutdown metrics: %v", err)
	}
}

func TestInactiveMetricsCollectorStillValidates(t *testing.T) {
	t.Parallel()

	provider := sdkmetric.NewMeterProvider()
	collector := otelsdk.NewMetricsCollector(provider.Meter("inactive"), nil)
	if collector.Active() {
		t.Fatal("collector without provider must be inactive")
	}
	valid := interfaces.NewMetricRecord(time.Now(), "requests", interfaces.MetricKindCounter, 1, nil, nil)
	if err := collector.Emit(valid); err != nil {
		t.Fatalf("inactive valid emit failed: %v", err)
	}
	if err := collector.Flush(context.Background()); err != nil {
		t.Fatalf("inactive flush failed: %v", err)
	}
	if err := collector.Shutdown(context.Background()); err != nil {
		t.Fatalf("inactive shutdown failed: %v", err)
	}
	for _, mutate := range []func(*interfaces.MetricRecord){
		func(record *interfaces.MetricRecord) { record.Name = " " },
		func(record *interfaces.MetricRecord) { record.Kind = "unknown" },
		func(record *interfaces.MetricRecord) { record.Value = math.NaN() },
		func(record *interfaces.MetricRecord) {
			record.Kind = interfaces.MetricKindCounter
			record.Value = -1
		},
		func(record *interfaces.MetricRecord) { record.Attributes = map[string]any{"bad": nil} },
	} {
		candidate := valid.Clone()
		mutate(&candidate)
		assertProblemID(t, collector.Emit(candidate), otel.FaultRecordInvalid)
		assertProblemID(t, otelsdk.ValidateMetricRecord(candidate), otel.FaultRecordInvalid)
	}
	for _, kind := range []interfaces.MetricKind{
		interfaces.MetricKindCounter,
		interfaces.MetricKindGauge,
		interfaces.MetricKindHistogram,
	} {
		if !otelsdk.ValidMetricKind(kind) {
			t.Errorf("valid kind rejected: %q", kind)
		}
	}
	if otelsdk.ValidMetricKind("unknown") {
		t.Fatal("unknown metric kind accepted")
	}
}

func TestMetricsLifecycleFailuresAreProblemTyped(t *testing.T) {
	t.Parallel()

	flushCause := errors.New("flush failed")
	exporter := &recordingMetricExporter{flushErr: flushCause}
	reader := sdkmetric.NewPeriodicReader(exporter, sdkmetric.WithInterval(time.Hour))
	provider := sdkmetric.NewMeterProvider(sdkmetric.WithReader(reader))
	collector := otelsdk.NewMetricsCollector(provider.Meter("flush"), provider)
	err := collector.Flush(context.Background())
	assertProblemID(t, err, otel.FaultFlushFailed)
	if !errors.Is(err, flushCause) {
		t.Fatalf("flush cause lost: %v", err)
	}
	_ = collector.Shutdown(context.Background())

	shutdownCause := errors.New("shutdown failed")
	exporter = &recordingMetricExporter{shutdownErr: shutdownCause}
	reader = sdkmetric.NewPeriodicReader(exporter, sdkmetric.WithInterval(time.Hour))
	provider = sdkmetric.NewMeterProvider(sdkmetric.WithReader(reader))
	collector = otelsdk.NewMetricsCollector(provider.Meter("shutdown"), provider)
	err = collector.Shutdown(context.Background())
	assertProblemID(t, err, otel.FaultShutdownFailed)
	if !errors.Is(err, shutdownCause) {
		t.Fatalf("shutdown cause lost: %v", err)
	}
}
