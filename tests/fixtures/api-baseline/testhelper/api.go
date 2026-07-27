package testhelper

import (
	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
	"github.com/AtomiCloud/diene.go-otel/adapters/otelsdk"
	"github.com/AtomiCloud/diene.go-otel/lib/otel"
)

type TestingT interface {
	Helper()
	Fatalf(format string, args ...any)
}

type InMemoryLoggerSink struct{}

func NewInMemoryLoggerSink() *InMemoryLoggerSink            { return nil }
func (*InMemoryLoggerSink) EnqueueResult(error)             {}
func (*InMemoryLoggerSink) Emit(interfaces.LogRecord) error { return nil }
func (*InMemoryLoggerSink) Records() []interfaces.LogRecord { return nil }
func (*InMemoryLoggerSink) Reset()                          {}

type InMemoryMetricsCollector struct{}

func NewInMemoryMetricsCollector() *InMemoryMetricsCollector         { return nil }
func (*InMemoryMetricsCollector) EnqueueResult(error)                {}
func (*InMemoryMetricsCollector) Emit(interfaces.MetricRecord) error { return nil }
func (*InMemoryMetricsCollector) Records() []interfaces.MetricRecord { return nil }
func (*InMemoryMetricsCollector) Reset()                             {}

type InMemoryTraceEmitter struct{ uncomparable []struct{} }

func NewInMemoryTraceEmitter() *InMemoryTraceEmitter      { return nil }
func (*InMemoryTraceEmitter) EnqueueResult(error)         {}
func (*InMemoryTraceEmitter) Emit(otel.TraceRecord) error { return nil }
func (*InMemoryTraceEmitter) Records() []otel.TraceRecord { return nil }
func (*InMemoryTraceEmitter) Reset()                      {}

func CheckTraceRecords([]otel.TraceRecord, []otel.TraceRecord) error { return nil }

func CheckTraceRecord(otel.TraceRecord, otel.TraceRecord) error { return nil }

func CheckAttributes(map[string]any, map[string]any) error { return nil }

func EqualAttributeValue(any, any) bool { return false }

func CheckOptionalString(string, *string, *string) error { return nil }

func CheckLogRecords([]interfaces.LogRecord, []interfaces.LogRecord) error { return nil }

func CheckMetricRecords([]interfaces.MetricRecord, []interfaces.MetricRecord) error { return nil }

func CheckResourceAttributes(map[string]string, map[string]string) error { return nil }

func CheckActiveSignals(otelsdk.ActiveSignals, otelsdk.ActiveSignals) error              { return nil }
func AssertTraceRecords(TestingT, *InMemoryTraceEmitter, []otel.TraceRecord)             {}
func AssertLogRecords(TestingT, *InMemoryLoggerSink, []interfaces.LogRecord)             {}
func AssertMetricRecords(TestingT, *InMemoryMetricsCollector, []interfaces.MetricRecord) {}
func AssertResourceAttributes(TestingT, map[string]string, map[string]string)            {}
func AssertActiveSignals(TestingT, otelsdk.ActiveSignals, otelsdk.ActiveSignals)         {}
func AssertProblemFault(TestingT, error, string)                                         {}
func CheckProblemFault(error, string) error                                              { return nil }

func FaultTypeURI(error) string { return "" }

func SampleConfig() otel.Config                   { return otel.Config{} }
func SampleIdentity() otel.AppIdentity            { return otel.AppIdentity{} }
func SampleTraceRecord() otel.TraceRecord         { return otel.TraceRecord{} }
func SampleLogRecord() interfaces.LogRecord       { return interfaces.LogRecord{} }
func SampleMetricRecord() interfaces.MetricRecord { return interfaces.MetricRecord{} }
