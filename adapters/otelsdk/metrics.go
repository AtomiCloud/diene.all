package otelsdk

import (
	"context"
	"sync"

	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
	"github.com/AtomiCloud/diene.go-otel/lib/otel"
	"go.opentelemetry.io/otel/metric"
	sdkmetric "go.opentelemetry.io/otel/sdk/metric"
)

// InstrumentKey joins a metric name and unit into the SDK's instrument identity.
// The SDK requires one instrument per (name, unit) pair, while the portable seam
// is sample-oriented, so instruments are cached under this key.
func InstrumentKey(name, unit string) string { return name + "\x00" + unit }

// InstrumentCache lazily creates and caches the instruments a sample stream
// needs. It is safe for concurrent use.
type InstrumentCache struct {
	meter      metric.Meter
	mutex      sync.Mutex
	counters   map[string]metric.Float64Counter
	gauges     map[string]metric.Float64Gauge
	histograms map[string]metric.Float64Histogram
}

// NewInstrumentCache builds an instrument cache over meter.
func NewInstrumentCache(meter metric.Meter) *InstrumentCache {
	return &InstrumentCache{
		meter:      meter,
		counters:   map[string]metric.Float64Counter{},
		gauges:     map[string]metric.Float64Gauge{},
		histograms: map[string]metric.Float64Histogram{},
	}
}

// Counter returns the cached counter for name and unit, creating it on first use.
func (c *InstrumentCache) Counter(name, unit string) (metric.Float64Counter, error) {
	c.mutex.Lock()
	defer c.mutex.Unlock()
	key := InstrumentKey(name, unit)
	if cached, found := c.counters[key]; found {
		return cached, nil
	}
	instrument, err := c.meter.Float64Counter(name, metric.WithUnit(unit))
	if err != nil {
		return nil, otel.WrapFault(otel.FaultEmitFailed, "Telemetry emission failed",
			"the counter "+name+" could not be created", otel.FaultStatusUnavailable, err)
	}
	c.counters[key] = instrument
	return instrument, nil
}

// Gauge returns the cached gauge for name and unit, creating it on first use.
func (c *InstrumentCache) Gauge(name, unit string) (metric.Float64Gauge, error) {
	c.mutex.Lock()
	defer c.mutex.Unlock()
	key := InstrumentKey(name, unit)
	if cached, found := c.gauges[key]; found {
		return cached, nil
	}
	instrument, err := c.meter.Float64Gauge(name, metric.WithUnit(unit))
	if err != nil {
		return nil, otel.WrapFault(otel.FaultEmitFailed, "Telemetry emission failed",
			"the gauge "+name+" could not be created", otel.FaultStatusUnavailable, err)
	}
	c.gauges[key] = instrument
	return instrument, nil
}

// Histogram returns the cached histogram for name and unit, creating it on first use.
func (c *InstrumentCache) Histogram(name, unit string) (metric.Float64Histogram, error) {
	c.mutex.Lock()
	defer c.mutex.Unlock()
	key := InstrumentKey(name, unit)
	if cached, found := c.histograms[key]; found {
		return cached, nil
	}
	instrument, err := c.meter.Float64Histogram(name, metric.WithUnit(unit))
	if err != nil {
		return nil, otel.WrapFault(otel.FaultEmitFailed, "Telemetry emission failed",
			"the histogram "+name+" could not be created", otel.FaultStatusUnavailable, err)
	}
	c.histograms[key] = instrument
	return instrument, nil
}

// MetricsCollector records application metric samples through the OpenTelemetry
// metrics SDK.
type MetricsCollector struct {
	instruments *InstrumentCache
	provider    *sdkmetric.MeterProvider
	active      bool
}

// NewMetricsCollector builds a metrics collector over meter. A nil provider marks
// the collector INACTIVE: records are still validated so consumer bugs surface in
// every landscape, but no instrument is created and nothing is exported.
func NewMetricsCollector(meter metric.Meter, provider *sdkmetric.MeterProvider) *MetricsCollector {
	return &MetricsCollector{
		instruments: NewInstrumentCache(meter),
		provider:    provider,
		active:      provider != nil,
	}
}

// Active reports whether samples reach an exporter.
func (c *MetricsCollector) Active() bool { return c.active }

// Emit delivers record.
func (c *MetricsCollector) Emit(record interfaces.MetricRecord) error {
	if err := ValidateMetricRecord(record); err != nil {
		return err
	}
	if !c.active {
		return nil
	}
	unit := ""
	if record.Unit != nil {
		unit = *record.Unit
	}
	attributes := metric.WithAttributes(Attributes(record.Attributes)...)
	switch record.Kind {
	case interfaces.MetricKindCounter:
		instrument, err := c.instruments.Counter(record.Name, unit)
		if err != nil {
			return err
		}
		instrument.Add(context.Background(), record.Value, attributes)
	case interfaces.MetricKindGauge:
		instrument, err := c.instruments.Gauge(record.Name, unit)
		if err != nil {
			return err
		}
		instrument.Record(context.Background(), record.Value, attributes)
	case interfaces.MetricKindHistogram:
		instrument, err := c.instruments.Histogram(record.Name, unit)
		if err != nil {
			return err
		}
		instrument.Record(context.Background(), record.Value, attributes)
	default:
		// ValidateMetricRecord rejects unknown kinds before dispatch.
	}
	return nil
}

// Flush exports every buffered metric sample.
func (c *MetricsCollector) Flush(ctx context.Context) error {
	if c.provider == nil {
		return nil
	}
	if err := c.provider.ForceFlush(ctx); err != nil {
		return otel.WrapFault(otel.FaultFlushFailed, "Telemetry flush failed",
			"the metrics pipeline could not be flushed", otel.FaultStatusUnavailable, err)
	}
	return nil
}

// Shutdown stops the metrics pipeline.
func (c *MetricsCollector) Shutdown(ctx context.Context) error {
	if c.provider == nil {
		return nil
	}
	if err := c.provider.Shutdown(ctx); err != nil {
		return otel.WrapFault(otel.FaultShutdownFailed, "Telemetry shutdown failed",
			"the metrics pipeline could not be shut down", otel.FaultStatusUnavailable, err)
	}
	return nil
}

// ValidateMetricRecord reports whether record can be emitted: a non-blank name, a
// known kind, a finite value, and portable attribute values.
func ValidateMetricRecord(record interfaces.MetricRecord) error {
	return otel.ValidateMetricRecord(record)
}

// ValidMetricKind reports whether kind is a member of the shared vocabulary.
func ValidMetricKind(kind interfaces.MetricKind) bool {
	return otel.ValidMetricKind(kind)
}
