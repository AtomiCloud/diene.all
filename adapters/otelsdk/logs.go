package otelsdk

import (
	"context"
	"io"

	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
	"github.com/AtomiCloud/diene.go-otel/adapters/otelsdk/internal/logbridge"
	"github.com/AtomiCloud/diene.go-otel/lib/otel"
	"github.com/rs/zerolog"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/sdk/resource"
	"go.opentelemetry.io/otel/trace"
)

// Trace-correlation and diagnostic field names written on every log record,
// matching the OpenTelemetry logs data model.
const (
	// FieldTraceID carries the active trace id.
	FieldTraceID = "trace_id"
	// FieldSpanID carries the active span id.
	FieldSpanID = "span_id"
	// FieldTraceFlags carries the active sampling flags.
	FieldTraceFlags = "trace_flags"
	// FieldError carries the log record's error description.
	FieldError = "error"
	// FieldStackTrace carries the log record's stack trace.
	FieldStackTrace = "stack_trace"
)

// LogSeverityFor maps a portable log level onto its numeric OpenTelemetry
// severity. The numeric form is returned so the mapping is assertable without
// naming a pre-1.0 type.
func LogSeverityFor(level interfaces.LogLevel) int {
	switch level {
	case interfaces.LogLevelTrace:
		return logbridge.SeverityTrace
	case interfaces.LogLevelDebug:
		return logbridge.SeverityDebug
	case interfaces.LogLevelInfo:
		return logbridge.SeverityInfo
	case interfaces.LogLevelWarning:
		return logbridge.SeverityWarn
	case interfaces.LogLevelError:
		return logbridge.SeverityError
	case interfaces.LogLevelFatal:
		return logbridge.SeverityFatal
	default:
		return logbridge.SeverityUndefined
	}
}

// ValidLogLevel reports whether level is a member of the shared vocabulary.
func ValidLogLevel(level interfaces.LogLevel) bool {
	return otel.ValidLogLevel(level)
}

// ZerologLevel maps a portable log level onto its zerolog level.
func ZerologLevel(level interfaces.LogLevel) zerolog.Level {
	switch level {
	case interfaces.LogLevelTrace:
		return zerolog.TraceLevel
	case interfaces.LogLevelDebug:
		return zerolog.DebugLevel
	case interfaces.LogLevelInfo:
		return zerolog.InfoLevel
	case interfaces.LogLevelWarning:
		return zerolog.WarnLevel
	case interfaces.LogLevelError:
		return zerolog.ErrorLevel
	case interfaces.LogLevelFatal:
		return zerolog.FatalLevel
	default:
		return zerolog.NoLevel
	}
}

// ValidateLogRecord reports whether record can be emitted: a known level and
// portable attribute values.
func ValidateLogRecord(record interfaces.LogRecord) error {
	return otel.ValidateLogRecord(record)
}

// TraceCorrelation returns the trace-correlation fields of ctx's active span, or
// an empty map when no valid span is active.
func TraceCorrelation(ctx context.Context) map[string]string {
	if ctx == nil {
		return map[string]string{}
	}
	spanContext := trace.SpanContextFromContext(ctx)
	if !spanContext.IsValid() {
		return map[string]string{}
	}
	return map[string]string{
		FieldTraceID:    spanContext.TraceID().String(),
		FieldSpanID:     spanContext.SpanID().String(),
		FieldTraceFlags: spanContext.TraceFlags().String(),
	}
}

// LogAttributesFor returns the OpenTelemetry attributes of one log record,
// including its optional error and stack-trace fields. Only the v1-stable
// attribute type appears here.
func LogAttributesFor(record interfaces.LogRecord) []attribute.KeyValue {
	converted := Attributes(record.Attributes)
	if record.Error != nil {
		converted = append(converted, attribute.String(FieldError, *record.Error))
	}
	if record.StackTrace != nil {
		converted = append(converted, attribute.String(FieldStackTrace, *record.StackTrace))
	}
	return converted
}

// LoggerSink emits structured application logs to a console (stdout) stream and,
// when the OTLP exporter is selected, through the OpenTelemetry logs pipeline.
//
// The console stream is zerolog JSON, which is the path the fleet's collector
// scrapes; the OTLP bridge is real rather than stubbed because the Go logs SDK is
// available. Its pre-1.0 types stay confined to an internal bridge package.
type LoggerSink struct {
	logger   *zerolog.Logger
	pipeline *logbridge.Provider
	console  bool
	ctx      context.Context
}

// NewLoggerSink builds a logs sink.
//
// Console output is written to writer with resourceAttributes as base fields.
// Exporter is the opaque logs exporter handle: an undefined handle disables the
// OTLP bridge and leaves the sink console-only, which is the default posture in a
// landscape whose overlay has not enabled OTLP.
func NewLoggerSink(
	ctx context.Context,
	writer io.Writer,
	resourceAttributes map[string]string,
	console bool,
	exporter LogExporter,
	res *resource.Resource,
	scopeName string,
) *LoggerSink {
	if writer == nil {
		writer = io.Discard
	}
	base := zerolog.New(writer).Level(zerolog.TraceLevel).With()
	for name, value := range resourceAttributes {
		base = base.Str(name, value)
	}
	logger := base.Logger()
	sink := &LoggerSink{logger: &logger, console: console, ctx: ctx}
	if exporter.Defined() {
		sink.pipeline = logbridge.NewProvider(exporter.inner, res, scopeName)
	}
	return sink
}

// Active reports whether this sink exports anything.
func (s *LoggerSink) Active() bool { return s.console || s.pipeline != nil }

// WithContext returns a sink bound to ctx, so trace correlation fields come from
// that context's active span.
//
// The shared [interfaces.LoggerSink] seam carries no context parameter and Go has
// no ambient context, so a caller that wants trace-correlated logs binds the
// request context here or calls [LoggerSink.EmitContext] directly.
func (s *LoggerSink) WithContext(ctx context.Context) *LoggerSink {
	if ctx == nil {
		return s
	}
	bound := *s
	bound.ctx = ctx
	return &bound
}

// Emit delivers record using the sink's bound context.
func (s *LoggerSink) Emit(record interfaces.LogRecord) error {
	return s.EmitContext(s.ctx, record)
}

// EmitContext delivers record, correlating it with ctx's active span.
func (s *LoggerSink) EmitContext(ctx context.Context, record interfaces.LogRecord) error {
	if err := ValidateLogRecord(record); err != nil {
		return err
	}
	if ctx == nil {
		ctx = context.Background()
	}
	if s.console {
		event := s.logger.WithLevel(ZerologLevel(record.Level)).
			Time(zerolog.TimestampFieldName, record.Timestamp)
		for name, value := range TraceCorrelation(ctx) {
			event = event.Str(name, value)
		}
		if len(record.Attributes) > 0 {
			event = event.Fields(record.Attributes)
		}
		if record.Error != nil {
			event = event.Str(FieldError, *record.Error)
		}
		if record.StackTrace != nil {
			event = event.Str(FieldStackTrace, *record.StackTrace)
		}
		event.Msg(record.Message)
	}
	if s.pipeline != nil {
		s.pipeline.Emit(ctx, logbridge.Payload{
			Timestamp:    record.Timestamp,
			Severity:     LogSeverityFor(record.Level),
			SeverityText: string(record.Level),
			Body:         record.Message,
			Attributes:   LogAttributesFor(record),
		})
	}
	return nil
}

// Flush exports every buffered log record.
func (s *LoggerSink) Flush(ctx context.Context) error {
	if s.pipeline == nil {
		return nil
	}
	if err := s.pipeline.ForceFlush(ctx); err != nil {
		return otel.WrapFault(otel.FaultFlushFailed, "Telemetry flush failed",
			"the logs pipeline could not be flushed", otel.FaultStatusUnavailable, err)
	}
	return nil
}

// Shutdown stops the logs pipeline.
func (s *LoggerSink) Shutdown(ctx context.Context) error {
	if s.pipeline == nil {
		return nil
	}
	if err := s.pipeline.Shutdown(ctx); err != nil {
		return otel.WrapFault(otel.FaultShutdownFailed, "Telemetry shutdown failed",
			"the logs pipeline could not be shut down", otel.FaultStatusUnavailable, err)
	}
	return nil
}
