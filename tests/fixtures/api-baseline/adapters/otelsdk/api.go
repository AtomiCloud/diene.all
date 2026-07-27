package otelsdk

import (
	"context"
	"io"
	"time"

	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
	"github.com/AtomiCloud/diene.go-otel/lib/otel"
	"github.com/rs/zerolog"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/metric"
	sdkmetric "go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/trace"
)

type ActiveSignals struct {
	Logs    bool
	Metrics bool
	Traces  bool
}

type ExporterKind string

const (
	ExporterConsole ExporterKind = "console"
	ExporterOtlp    ExporterKind = "otlp"
)

func (k ExporterKind) String() string { return string(k) }

type (
	SpanExporterFactory   func(context.Context, ExporterKind, otel.OtlpSettings) (sdktrace.SpanExporter, error)
	MetricExporterFactory func(context.Context, ExporterKind, otel.OtlpSettings) (sdkmetric.Exporter, error)
	LogExporterFactory    func(context.Context, ExporterKind, otel.OtlpSettings) (LogExporter, error)
)

type Options struct {
	System             interfaces.System
	LogWriter          io.Writer
	LoggerSink         interfaces.LoggerSink
	MetricsCollector   interfaces.MetricsCollector
	TraceEmitter       otel.TraceEmitter
	SpanExporters      SpanExporterFactory
	MetricExporters    MetricExporterFactory
	LogExporters       LogExporterFactory
	GlobalRegistration bool
	Context            context.Context
}

type Option func(*Options) error

func DefaultOptions() Options                                 { return Options{} }
func WithSystem(interfaces.System) Option                     { return nil }
func WithLogWriter(io.Writer) Option                          { return nil }
func WithLoggerSink(interfaces.LoggerSink) Option             { return nil }
func WithMetricsCollector(interfaces.MetricsCollector) Option { return nil }
func WithTraceEmitter(otel.TraceEmitter) Option               { return nil }
func WithSpanExporterFactory(SpanExporterFactory) Option      { return nil }
func WithMetricExporterFactory(MetricExporterFactory) Option  { return nil }
func WithLogExporterFactory(LogExporterFactory) Option        { return nil }
func WithGlobalRegistration(bool) Option                      { return nil }
func ResolveOptions(...Option) (Options, error)               { return Options{}, nil }

func DefaultSpanExporterFactory(context.Context, ExporterKind, otel.OtlpSettings) (sdktrace.SpanExporter, error) {
	return nil, nil
}

func DefaultMetricExporterFactory(context.Context, ExporterKind, otel.OtlpSettings) (sdkmetric.Exporter, error) {
	return nil, nil
}

func DefaultLogExporterFactory(context.Context, ExporterKind, otel.OtlpSettings) (LogExporter, error) {
	return LogExporter{}, nil
}
func UnknownExporterFault(ExporterKind) error { return nil }

type LogExporter struct{}

func (LogExporter) Defined() bool                          { return false }
func NewConsoleLogExporter(io.Writer) (LogExporter, error) { return LogExporter{}, nil }
func NewOtlpLogExporter(context.Context, otel.OtlpSettings) (LogExporter, error) {
	return LogExporter{}, nil
}

type CapturedLogRecord struct {
	Timestamp    time.Time
	Severity     int
	SeverityText string
	Body         string
	Attributes   map[string]string
}

type LogCapture struct{}

func (*LogCapture) Records() []CapturedLogRecord          { return nil }
func (*LogCapture) Reset()                                {}
func NewRecordingLogExporter() (LogExporter, *LogCapture) { return LogExporter{}, nil }
func LogAttributeValueString(attribute.Value) string      { return "" }

const (
	FieldTraceID    = "trace_id"
	FieldSpanID     = "span_id"
	FieldTraceFlags = "trace_flags"
	FieldError      = "error"
	FieldStackTrace = "stack_trace"
)

func LogSeverityFor(interfaces.LogLevel) int                     { return 0 }
func ValidLogLevel(interfaces.LogLevel) bool                     { return false }
func ZerologLevel(interfaces.LogLevel) zerolog.Level             { return zerolog.NoLevel }
func ValidateLogRecord(interfaces.LogRecord) error               { return nil }
func TraceCorrelation(context.Context) map[string]string         { return nil }
func LogAttributesFor(interfaces.LogRecord) []attribute.KeyValue { return nil }

type LoggerSink struct{}

func NewLoggerSink(context.Context, io.Writer, map[string]string, bool, LogExporter, *resource.Resource, string) *LoggerSink {
	return nil
}
func (*LoggerSink) Active() bool                                            { return false }
func (*LoggerSink) WithContext(context.Context) *LoggerSink                 { return nil }
func (*LoggerSink) Emit(interfaces.LogRecord) error                         { return nil }
func (*LoggerSink) EmitContext(context.Context, interfaces.LogRecord) error { return nil }
func (*LoggerSink) Flush(context.Context) error                             { return nil }
func (*LoggerSink) Shutdown(context.Context) error                          { return nil }

func Attributes(map[string]any) []attribute.KeyValue   { return nil }
func Attribute(string, any) (attribute.KeyValue, bool) { return attribute.KeyValue{}, false }
func RepresentableUnsigned(uint64) bool                { return false }

func InstrumentKey(string, string) string { return "" }

type InstrumentCache struct{ uncomparable map[string]struct{} }

func NewInstrumentCache(metric.Meter) *InstrumentCache                         { return nil }
func (*InstrumentCache) Counter(string, string) (metric.Float64Counter, error) { return nil, nil }

func (*InstrumentCache) Gauge(string, string) (metric.Float64Gauge, error) { return nil, nil }

func (*InstrumentCache) Histogram(string, string) (metric.Float64Histogram, error) { return nil, nil }

type MetricsCollector struct{}

func NewMetricsCollector(metric.Meter, *sdkmetric.MeterProvider) *MetricsCollector { return nil }
func (*MetricsCollector) Active() bool                                             { return false }
func (*MetricsCollector) Emit(interfaces.MetricRecord) error                       { return nil }
func (*MetricsCollector) Flush(context.Context) error                              { return nil }
func (*MetricsCollector) Shutdown(context.Context) error                           { return nil }
func ValidateMetricRecord(interfaces.MetricRecord) error                           { return nil }
func ValidMetricKind(interfaces.MetricKind) bool                                   { return false }

func NewSampler(otel.SamplerConfig, interfaces.System) (sdktrace.Sampler, error) { return nil, nil }

type TraceEmitter struct{}

func NewTraceEmitter(trace.Tracer, *sdktrace.TracerProvider) *TraceEmitter { return nil }
func NewInactiveTraceEmitter(string) *TraceEmitter                         { return nil }
func (*TraceEmitter) Active() bool                                         { return false }
func (*TraceEmitter) Emit(otel.TraceRecord) error                          { return nil }
func (*TraceEmitter) EmitContext(context.Context, otel.TraceRecord) error  { return nil }
func (*TraceEmitter) Flush(context.Context) error                          { return nil }
func (*TraceEmitter) Shutdown(context.Context) error                       { return nil }
func SpanStatusCode(otel.TraceStatus) codes.Code                           { return codes.Unset }

type Runtime struct{ uncomparable map[string]struct{} }

func New(context.Context, otel.Config, otel.AppIdentity, ...Option) (*Runtime, error) {
	return nil, nil
}
func NewResource(map[string]string) *resource.Resource   { return nil }
func DisabledSelections() map[otel.Signal]otel.Selection { return nil }
func SignalSelections(otel.Config, interfaces.System) (map[otel.Signal]otel.Selection, error) {
	return nil, nil
}
func (*Runtime) Config() otel.Config                                     { return otel.Config{} }
func (*Runtime) Identity() otel.AppIdentity                              { return otel.AppIdentity{} }
func (*Runtime) Resource() *resource.Resource                            { return nil }
func (*Runtime) ResourceAttributes() map[string]string                   { return nil }
func (*Runtime) Active() ActiveSignals                                   { return ActiveSignals{} }
func (*Runtime) LoggerSink() interfaces.LoggerSink                       { return nil }
func (*Runtime) MetricsCollector() interfaces.MetricsCollector           { return nil }
func (*Runtime) TraceEmitter() otel.TraceEmitter                         { return nil }
func (*Runtime) Tracer() trace.Tracer                                    { return nil }
func (*Runtime) Meter() metric.Meter                                     { return nil }
func (*Runtime) LoggerSinkContext(context.Context) interfaces.LoggerSink { return nil }
func (*Runtime) Flush(context.Context) error                             { return nil }
func (*Runtime) Shutdown(context.Context) error                          { return nil }
func (*Runtime) BuildLogs(context.Context, otel.Config, map[otel.Signal]otel.Selection, Options, *resource.Resource, string, map[otel.Signal]struct{}) error {
	return nil
}

func (*Runtime) BuildMetrics(context.Context, otel.Config, map[otel.Signal]otel.Selection, Options, *resource.Resource, string, map[otel.Signal]struct{}) error {
	return nil
}

func (*Runtime) BuildTraces(context.Context, otel.Config, map[otel.Signal]otel.Selection, Options, *resource.Resource, string, map[otel.Signal]struct{}) error {
	return nil
}
func SelectedKinds(otel.Selection) []ExporterKind    { return nil }
func (*Runtime) Register()                           {}
func TracerProviderOf(*Runtime) trace.TracerProvider { return nil }
func MeterProviderOf(*Runtime) metric.MeterProvider  { return nil }

type System struct{}

func NewSystem() *System                                   { return nil }
func (*System) Environment(string) (*string, error)        { return nil, nil }
func (*System) CurrentDirectory() (string, error)          { return "", nil }
func (*System) NowUTC() (time.Time, error)                 { return time.Time{}, nil }
func (*System) Delay(context.Context, time.Duration) error { return nil }
