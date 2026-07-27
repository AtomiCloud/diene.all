// Package testhelper ships the consumer-facing telemetry test doubles and
// assertions for Diene's Go OpenTelemetry engine.
//
// Telemetry infrastructure is NEVER started to test a consumer: integration tests
// inject these in-memory doubles instead. The trace double lives here rather than
// in the shared interfaces library because the trace seam is language-local.
//
// Every assertion is offered twice: a Check* form returning an error, and an
// Assert* form failing a test through [TestingT]. The pair is what lets the meta
// tier prove each assertion fails on known-bad input and passes on known-good
// input without a fake testing.T.
package testhelper

import (
	"errors"
	"fmt"
	"maps"
	"reflect"
	"sync"
	"time"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
	interfaceshelper "github.com/AtomiCloud/diene.go-interfaces/testhelper"
	"github.com/AtomiCloud/diene.go-otel/adapters/otelsdk"
	"github.com/AtomiCloud/diene.go-otel/lib/otel"
)

// TestingT is the subset of testing.TB these assertions need.
type TestingT interface {
	// Helper marks the caller as a test helper.
	Helper()
	// Fatalf reports a fatal failure.
	Fatalf(format string, args ...any)
}

// InMemoryLoggerSink is the published interfaces double with the engine's
// validation contract layered in front of it. This makes its accepted emit
// surface identical to the real SDK sink while preserving the upstream FIFO
// scripting and cloning semantics.
type InMemoryLoggerSink struct {
	mutex sync.Mutex
	inner *interfaceshelper.InMemoryLoggerSink
}

// NewInMemoryLoggerSink creates an empty logs double.
func NewInMemoryLoggerSink() *InMemoryLoggerSink {
	return &InMemoryLoggerSink{inner: interfaceshelper.NewInMemoryLoggerSink()}
}

// EnqueueResult scripts the next successful-validation log emission outcome.
func (s *InMemoryLoggerSink) EnqueueResult(err error) {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	s.inner.EnqueueResult(err)
}

// Emit validates and records one log emission.
func (s *InMemoryLoggerSink) Emit(record interfaces.LogRecord) error {
	if err := otel.ValidateLogRecord(record); err != nil {
		return err
	}
	s.mutex.Lock()
	defer s.mutex.Unlock()
	return s.inner.Emit(record)
}

// Records returns an independently owned snapshot of emitted logs.
func (s *InMemoryLoggerSink) Records() []interfaces.LogRecord {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	return s.inner.Records()
}

// Reset discards every recorded log and scripted result.
func (s *InMemoryLoggerSink) Reset() {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	s.inner = interfaceshelper.NewInMemoryLoggerSink()
}

// InMemoryMetricsCollector is the published interfaces double with the engine's
// validation contract layered in front of it.
type InMemoryMetricsCollector struct {
	mutex sync.Mutex
	inner *interfaceshelper.InMemoryMetricsCollector
}

// NewInMemoryMetricsCollector creates an empty metrics double.
func NewInMemoryMetricsCollector() *InMemoryMetricsCollector {
	return &InMemoryMetricsCollector{inner: interfaceshelper.NewInMemoryMetricsCollector()}
}

// EnqueueResult scripts the next successful-validation metric emission outcome.
func (c *InMemoryMetricsCollector) EnqueueResult(err error) {
	c.mutex.Lock()
	defer c.mutex.Unlock()
	c.inner.EnqueueResult(err)
}

// Emit validates and records one metric emission.
func (c *InMemoryMetricsCollector) Emit(record interfaces.MetricRecord) error {
	if err := otel.ValidateMetricRecord(record); err != nil {
		return err
	}
	c.mutex.Lock()
	defer c.mutex.Unlock()
	return c.inner.Emit(record)
}

// Records returns an independently owned snapshot of emitted metrics.
func (c *InMemoryMetricsCollector) Records() []interfaces.MetricRecord {
	c.mutex.Lock()
	defer c.mutex.Unlock()
	return c.inner.Records()
}

// Reset discards every recorded metric and scripted result.
func (c *InMemoryMetricsCollector) Reset() {
	c.mutex.Lock()
	defer c.mutex.Unlock()
	c.inner = interfaceshelper.NewInMemoryMetricsCollector()
}

// InMemoryTraceEmitter is a deterministic [otel.TraceEmitter] double. It records
// every accepted span and can be scripted to fail, so a consumer proves its own
// error handling without a collector. It is safe for concurrent use.
type InMemoryTraceEmitter struct {
	mutex    sync.Mutex
	records  []otel.TraceRecord
	failures []error
}

// NewInMemoryTraceEmitter creates a trace double.
func NewInMemoryTraceEmitter() *InMemoryTraceEmitter { return &InMemoryTraceEmitter{} }

// EnqueueResult scripts the next emission outcome. Scripted results are consumed
// in FIFO order, matching the shared doubles' idiom.
func (e *InMemoryTraceEmitter) EnqueueResult(err error) {
	e.mutex.Lock()
	defer e.mutex.Unlock()
	e.failures = append(e.failures, err)
}

// Emit delivers record, honoring any scripted result. A record that fails
// validation is rejected exactly as the real emitter rejects it, so the double
// cannot accept telemetry the SDK would refuse.
func (e *InMemoryTraceEmitter) Emit(record otel.TraceRecord) error {
	if err := record.Validate(); err != nil {
		return err
	}
	e.mutex.Lock()
	defer e.mutex.Unlock()
	if len(e.failures) > 0 {
		scripted := e.failures[0]
		e.failures = e.failures[1:]
		if scripted != nil {
			return otel.NormalizeFault(scripted)
		}
	}
	e.records = append(e.records, record.Clone())
	return nil
}

// Records returns an independently owned snapshot of every accepted span.
func (e *InMemoryTraceEmitter) Records() []otel.TraceRecord {
	e.mutex.Lock()
	defer e.mutex.Unlock()
	snapshot := make([]otel.TraceRecord, 0, len(e.records))
	for _, record := range e.records {
		snapshot = append(snapshot, record.Clone())
	}
	return snapshot
}

// Reset discards every recorded span and scripted result.
func (e *InMemoryTraceEmitter) Reset() {
	e.mutex.Lock()
	defer e.mutex.Unlock()
	e.records = nil
	e.failures = nil
}

// CheckTraceRecords reports whether actual equals want, span for span.
func CheckTraceRecords(actual, want []otel.TraceRecord) error {
	if len(actual) != len(want) {
		return fmt.Errorf("trace records: expected %d, got %d", len(want), len(actual))
	}
	for index := range want {
		if err := CheckTraceRecord(actual[index], want[index]); err != nil {
			return fmt.Errorf("trace record %d: %w", index, err)
		}
	}
	return nil
}

// CheckTraceRecord reports whether one span equals want.
func CheckTraceRecord(actual, want otel.TraceRecord) error {
	if actual.Name != want.Name {
		return fmt.Errorf("name: expected %q, got %q", want.Name, actual.Name)
	}
	if !actual.Timestamp.Equal(want.Timestamp) {
		return fmt.Errorf("timestamp: expected %s, got %s", want.Timestamp, actual.Timestamp)
	}
	if actual.Status != want.Status {
		return fmt.Errorf("status: expected %q, got %q", want.Status, actual.Status)
	}
	if err := CheckOptionalString("status message", actual.StatusMessage, want.StatusMessage); err != nil {
		return err
	}
	if err := CheckAttributes(actual.Attributes, want.Attributes); err != nil {
		return err
	}
	if len(actual.Events) != len(want.Events) {
		return fmt.Errorf("events: expected %d, got %d", len(want.Events), len(actual.Events))
	}
	for index := range want.Events {
		if actual.Events[index].Name != want.Events[index].Name {
			return fmt.Errorf("event %d name: expected %q, got %q",
				index, want.Events[index].Name, actual.Events[index].Name)
		}
		if err := CheckAttributes(actual.Events[index].Attributes, want.Events[index].Attributes); err != nil {
			return fmt.Errorf("event %d: %w", index, err)
		}
	}
	return nil
}

// CheckAttributes reports whether two attribute maps are equal, treating nil and
// empty as the same absence of attributes.
func CheckAttributes(actual, want map[string]any) error {
	if len(actual) != len(want) {
		return fmt.Errorf("attributes: expected %d, got %d", len(want), len(actual))
	}
	for name, wanted := range want {
		got, present := actual[name]
		if !present {
			return fmt.Errorf("attributes: %q is missing", name)
		}
		if !EqualAttributeValue(got, wanted) {
			return fmt.Errorf("attribute %q: expected %v, got %v", name, wanted, got)
		}
	}
	return nil
}

// EqualAttributeValue compares two attribute values, comparing slices member-wise.
func EqualAttributeValue(actual, want any) bool {
	return reflect.DeepEqual(actual, want)
}

// CheckOptionalString reports whether two optional strings agree.
func CheckOptionalString(label string, actual, want *string) error {
	switch {
	case actual == nil && want == nil:
		return nil
	case actual == nil:
		return fmt.Errorf("%s: expected %q, got absent", label, *want)
	case want == nil:
		return fmt.Errorf("%s: expected absent, got %q", label, *actual)
	case *actual != *want:
		return fmt.Errorf("%s: expected %q, got %q", label, *want, *actual)
	default:
		return nil
	}
}

// CheckLogRecords reports whether actual equals want, record for record.
func CheckLogRecords(actual, want []interfaces.LogRecord) error {
	if len(actual) != len(want) {
		return fmt.Errorf("log records: expected %d, got %d", len(want), len(actual))
	}
	for index := range want {
		if actual[index].Level != want[index].Level {
			return fmt.Errorf("log record %d level: expected %q, got %q",
				index, want[index].Level, actual[index].Level)
		}
		if actual[index].Message != want[index].Message {
			return fmt.Errorf("log record %d message: expected %q, got %q",
				index, want[index].Message, actual[index].Message)
		}
		if !actual[index].Timestamp.Equal(want[index].Timestamp) {
			return fmt.Errorf("log record %d timestamp: expected %s, got %s",
				index, want[index].Timestamp, actual[index].Timestamp)
		}
		if err := CheckAttributes(actual[index].Attributes, want[index].Attributes); err != nil {
			return fmt.Errorf("log record %d: %w", index, err)
		}
		if err := CheckOptionalString(fmt.Sprintf("log record %d error", index),
			actual[index].Error, want[index].Error); err != nil {
			return err
		}
		if err := CheckOptionalString(fmt.Sprintf("log record %d stack trace", index),
			actual[index].StackTrace, want[index].StackTrace); err != nil {
			return err
		}
	}
	return nil
}

// CheckMetricRecords reports whether actual equals want, sample for sample.
func CheckMetricRecords(actual, want []interfaces.MetricRecord) error {
	if len(actual) != len(want) {
		return fmt.Errorf("metric records: expected %d, got %d", len(want), len(actual))
	}
	for index := range want {
		if !actual[index].Timestamp.Equal(want[index].Timestamp) {
			return fmt.Errorf("metric record %d timestamp: expected %s, got %s",
				index, want[index].Timestamp, actual[index].Timestamp)
		}
		if actual[index].Name != want[index].Name {
			return fmt.Errorf("metric record %d name: expected %q, got %q",
				index, want[index].Name, actual[index].Name)
		}
		if actual[index].Kind != want[index].Kind {
			return fmt.Errorf("metric record %d kind: expected %q, got %q",
				index, want[index].Kind, actual[index].Kind)
		}
		if actual[index].Value != want[index].Value {
			return fmt.Errorf("metric record %d value: expected %v, got %v",
				index, want[index].Value, actual[index].Value)
		}
		if err := CheckOptionalString(fmt.Sprintf("metric record %d unit", index),
			actual[index].Unit, want[index].Unit); err != nil {
			return err
		}
		if err := CheckAttributes(actual[index].Attributes, want[index].Attributes); err != nil {
			return fmt.Errorf("metric record %d: %w", index, err)
		}
	}
	return nil
}

// CheckResourceAttributes reports whether two resource attribute maps are equal.
func CheckResourceAttributes(actual, want map[string]string) error {
	if !maps.Equal(actual, want) {
		return fmt.Errorf("resource attributes: expected %v, got %v", want, actual)
	}
	return nil
}

// CheckActiveSignals reports whether the runtime's active-signal state equals want.
func CheckActiveSignals(actual, want otelsdk.ActiveSignals) error {
	if actual != want {
		return fmt.Errorf("active signals: expected %+v, got %+v", want, actual)
	}
	return nil
}

// AssertTraceRecords fails t unless the double recorded exactly want.
func AssertTraceRecords(t TestingT, subject *InMemoryTraceEmitter, want []otel.TraceRecord) {
	t.Helper()
	if err := CheckTraceRecords(subject.Records(), want); err != nil {
		t.Fatalf("%v", err)
	}
}

// AssertLogRecords fails t unless the double recorded exactly want.
func AssertLogRecords(t TestingT, subject *InMemoryLoggerSink, want []interfaces.LogRecord) {
	t.Helper()
	if err := CheckLogRecords(subject.Records(), want); err != nil {
		t.Fatalf("%v", err)
	}
}

// AssertMetricRecords fails t unless the double recorded exactly want.
func AssertMetricRecords(t TestingT, subject *InMemoryMetricsCollector, want []interfaces.MetricRecord) {
	t.Helper()
	if err := CheckMetricRecords(subject.Records(), want); err != nil {
		t.Fatalf("%v", err)
	}
}

// AssertResourceAttributes fails t unless actual equals want.
func AssertResourceAttributes(t TestingT, actual, want map[string]string) {
	t.Helper()
	if err := CheckResourceAttributes(actual, want); err != nil {
		t.Fatalf("%v", err)
	}
}

// AssertActiveSignals fails t unless actual equals want.
func AssertActiveSignals(t TestingT, actual, want otelsdk.ActiveSignals) {
	t.Helper()
	if err := CheckActiveSignals(actual, want); err != nil {
		t.Fatalf("%v", err)
	}
}

// AssertProblemFault fails t unless err carries the engine fault id.
func AssertProblemFault(t TestingT, err error, id string) {
	t.Helper()
	if checkErr := CheckProblemFault(err, id); checkErr != nil {
		t.Fatalf("%v", checkErr)
	}
}

// CheckProblemFault reports whether err is a problem-typed engine fault with id.
func CheckProblemFault(err error, id string) error {
	if err == nil {
		return errors.New("expected a problem-typed fault, got nil")
	}
	actual := FaultTypeURI(err)
	if actual == "" {
		return fmt.Errorf("expected a problem-typed fault, got: %w", err)
	}
	want := otel.FaultProblem(id, "", "", 0).Type
	if actual != want {
		return fmt.Errorf("fault type: expected %q, got %q", want, actual)
	}
	return nil
}

// FaultTypeURI returns the RFC 9457 type URI err carries, or an empty string when
// err is not problem-typed.
func FaultTypeURI(err error) string {
	var problemErr *problem.Error
	if errors.As(err, &problemErr) && problemErr != nil {
		return problemErr.Problem.Type
	}
	return ""
}

// SampleConfig returns a valid OTLP-enabled block for consumer tests.
func SampleConfig() otel.Config {
	config := otel.DefaultConfig()
	endpoint := "https://collector.example:4318"
	config.Logs.Exporter.Otlp.Enabled = true
	config.Logs.Exporter.Otlp.Endpoint = endpoint
	config.Metrics.Exporter.Otlp.Enabled = true
	config.Metrics.Exporter.Otlp.Endpoint = endpoint
	config.Traces.Exporter.Otlp.Enabled = true
	config.Traces.Exporter.Otlp.Endpoint = endpoint
	return config
}

// SampleIdentity returns a valid service-tree identity for consumer tests.
func SampleIdentity() otel.AppIdentity {
	return otel.AppIdentity{
		Landscape: "lapras",
		Platform:  "diene",
		Service:   "otel",
		Module:    "engine",
		Version:   "1.0.0",
	}
}

// SampleTraceRecord returns a valid span for consumer tests.
func SampleTraceRecord() otel.TraceRecord {
	return otel.NewTraceRecord(
		time.Date(2026, 7, 25, 12, 0, 0, 0, time.UTC),
		"sample-span",
		map[string]any{"sample": true},
		[]otel.TraceEvent{otel.NewTraceEvent("sample-event", map[string]any{"index": 1})},
		otel.TraceStatusOK,
		nil,
	)
}

// SampleLogRecord returns a valid structured log for consumer tests.
func SampleLogRecord() interfaces.LogRecord {
	return interfaces.NewLogRecord(
		time.Date(2026, 7, 25, 12, 0, 0, 0, time.UTC),
		interfaces.LogLevelInfo,
		"sample-log",
		map[string]any{"sample": true},
		nil,
		nil,
	)
}

// SampleMetricRecord returns a valid counter sample for consumer tests.
func SampleMetricRecord() interfaces.MetricRecord {
	unit := "1"
	return interfaces.NewMetricRecord(
		time.Date(2026, 7, 25, 12, 0, 0, 0, time.UTC),
		"sample.counter",
		interfaces.MetricKindCounter,
		1,
		&unit,
		map[string]any{"sample": true},
	)
}

var (
	_ interfaces.LoggerSink       = (*InMemoryLoggerSink)(nil)
	_ interfaces.MetricsCollector = (*InMemoryMetricsCollector)(nil)
	_ otel.TraceEmitter           = (*InMemoryTraceEmitter)(nil)
)
