package otelsdk_test

import (
	"context"
	"errors"
	"sync"
	"testing"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
	interfaceshelper "github.com/AtomiCloud/diene.go-interfaces/testhelper"
	sdkmetric "go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/metric/metricdata"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
)

func assertProblemID(t *testing.T, err error, id string) {
	t.Helper()
	if err == nil {
		t.Fatalf("expected problem %q, got nil", id)
	}
	var problemErr *problem.Error
	if !errors.As(err, &problemErr) {
		t.Fatalf("expected problem %q, got %T: %v", id, err, err)
	}
	got, ok := problemErr.Problem.Data["id"].(string)
	if !ok || got != id {
		t.Fatalf("expected problem id %q, got %#v", id, problemErr.Problem.Data["id"])
	}
}

func systemWith(environment map[string]string) *interfaceshelper.InMemorySystem {
	return interfaceshelper.NewInMemorySystem(interfaceshelper.InMemorySystemOptions{
		Environment: environment,
	})
}

type recordingMetricExporter struct {
	mutex       sync.Mutex
	exports     []metricdata.ResourceMetrics
	exportErr   error
	flushErr    error
	shutdownErr error
	shutdowns   int
}

func (*recordingMetricExporter) Temporality(kind sdkmetric.InstrumentKind) metricdata.Temporality {
	return sdkmetric.DefaultTemporalitySelector(kind)
}

func (*recordingMetricExporter) Aggregation(kind sdkmetric.InstrumentKind) sdkmetric.Aggregation {
	return sdkmetric.DefaultAggregationSelector(kind)
}

func (e *recordingMetricExporter) Export(_ context.Context, metrics *metricdata.ResourceMetrics) error {
	e.mutex.Lock()
	defer e.mutex.Unlock()
	e.exports = append(e.exports, *metrics)
	return e.exportErr
}

func (e *recordingMetricExporter) ForceFlush(context.Context) error { return e.flushErr }

func (e *recordingMetricExporter) Shutdown(context.Context) error {
	e.mutex.Lock()
	defer e.mutex.Unlock()
	e.shutdowns++
	return e.shutdownErr
}

func (e *recordingMetricExporter) shutdownCount() int {
	e.mutex.Lock()
	defer e.mutex.Unlock()
	return e.shutdowns
}

func (e *recordingMetricExporter) metricNames() []string {
	e.mutex.Lock()
	defer e.mutex.Unlock()
	names := []string{}
	for _, exported := range e.exports {
		for _, scope := range exported.ScopeMetrics {
			for _, metric := range scope.Metrics {
				names = append(names, metric.Name)
			}
		}
	}
	return names
}

type lifecycleSpanProcessor struct {
	forceFlushErr error
	shutdownErr   error
	starts        int
	ends          int
}

func (p *lifecycleSpanProcessor) OnStart(context.Context, sdktrace.ReadWriteSpan) { p.starts++ }

func (p *lifecycleSpanProcessor) OnEnd(sdktrace.ReadOnlySpan) { p.ends++ }

func (p *lifecycleSpanProcessor) Shutdown(context.Context) error { return p.shutdownErr }

func (p *lifecycleSpanProcessor) ForceFlush(context.Context) error { return p.forceFlushErr }

type recordingSpanExporter struct {
	mutex       sync.Mutex
	spans       []sdktrace.ReadOnlySpan
	exportErr   error
	shutdownErr error
	shutdowns   int
}

func (e *recordingSpanExporter) ExportSpans(_ context.Context, spans []sdktrace.ReadOnlySpan) error {
	e.mutex.Lock()
	defer e.mutex.Unlock()
	e.spans = append(e.spans, spans...)
	return e.exportErr
}

func (e *recordingSpanExporter) Shutdown(context.Context) error {
	e.mutex.Lock()
	defer e.mutex.Unlock()
	e.shutdowns++
	return e.shutdownErr
}

func (e *recordingSpanExporter) shutdownCount() int {
	e.mutex.Lock()
	defer e.mutex.Unlock()
	return e.shutdowns
}
