package interfaces

import "time"

// MetricKind identifies how a metric sample is aggregated.
type MetricKind string

const (
	// MetricKindCounter identifies a monotonically accumulating value.
	MetricKindCounter MetricKind = "counter"
	// MetricKindGauge identifies an instantaneous value.
	MetricKindGauge MetricKind = "gauge"
	// MetricKindHistogram identifies a distribution observation.
	MetricKindHistogram MetricKind = "histogram"
)

// String returns the portable wire name of k.
func (k MetricKind) String() string { return string(k) }

// MetricRecord is one metric sample emitted by an application.
type MetricRecord struct {
	// Timestamp is when the sample was observed.
	Timestamp time.Time
	// Name is the metric name.
	Name string
	// Kind controls metric aggregation.
	Kind MetricKind
	// Value is the observed numeric value.
	Value float64
	// Unit is absent when the metric has no declared unit.
	Unit *string
	// Attributes is a structured, independently owned copy of caller input.
	Attributes map[string]any
}

// NewMetricRecord creates a record with copied attributes and optional unit.
func NewMetricRecord(timestamp time.Time, name string, kind MetricKind, value float64, unit *string, attributes map[string]any) MetricRecord {
	record := MetricRecord{Timestamp: timestamp.UTC(), Name: name, Kind: kind, Value: value, Attributes: CloneAttributes(attributes)}
	if unit != nil {
		copied := *unit
		record.Unit = &copied
	}
	return record
}

// Clone returns a record with independently owned attributes and optional unit.
func (r MetricRecord) Clone() MetricRecord {
	return NewMetricRecord(r.Timestamp, r.Name, r.Kind, r.Value, r.Unit, r.Attributes)
}

// MetricsCollector receives structured application metric samples.
type MetricsCollector interface {
	// Emit delivers record.
	Emit(record MetricRecord) error
}
