package otelsdk

import (
	"context"
	"io"
	"maps"
	"time"

	"github.com/AtomiCloud/diene.go-otel/adapters/otelsdk/internal/logbridge"
	"github.com/AtomiCloud/diene.go-otel/lib/otel"
	"go.opentelemetry.io/otel/attribute"
)

// LogExporter is an OPAQUE handle to a logs exporter.
//
// The logs signal of the OpenTelemetry Go SDK is still a pre-1.0 module, so its
// types never reach this library's public surface: a v0 breaking change would
// otherwise become a breaking change of this v1 module. Callers build exporters
// through the constructors below and never name an SDK log type.
type LogExporter struct {
	inner logbridge.Exporter
}

// Defined reports whether the handle carries an exporter.
func (e LogExporter) Defined() bool { return e.inner.Defined() }

// NewConsoleLogExporter builds the stdout logs exporter. A nil writer keeps the
// exporter's own default destination.
func NewConsoleLogExporter(writer io.Writer) (LogExporter, error) {
	exporter, err := logbridge.NewConsoleExporter(writer)
	return LogExporter{inner: exporter}, otel.NormalizeFault(err)
}

// NewOtlpLogExporter builds the OTLP http/protobuf logs exporter. Each nil field
// in settings is deliberately left unset so the exporter reads its own OTEL_*
// variable instead of being overridden by an explicit option.
func NewOtlpLogExporter(ctx context.Context, settings otel.OtlpSettings) (LogExporter, error) {
	if settings.URL != nil {
		if err := otel.ValidateOtlpEndpoint(*settings.URL); err != nil {
			return LogExporter{}, err
		}
	}
	exporter, err := logbridge.NewOtlpExporter(ctx, settings.URL, settings.Headers, settings.Timeout)
	return LogExporter{inner: exporter}, otel.NormalizeFault(err)
}

// CapturedLogRecord is one exported log record in this engine's own shape, so
// tests assert exported telemetry without naming an SDK log type.
type CapturedLogRecord struct {
	// Timestamp is when the event occurred.
	Timestamp time.Time
	// Severity is the numeric OpenTelemetry severity.
	Severity int
	// SeverityText is the portable level name.
	SeverityText string
	// Body is the log message.
	Body string
	// Attributes are the record's attributes in canonical string form.
	Attributes map[string]string
}

// LogCapture records everything a [LogExporter] built by
// [NewRecordingLogExporter] exports. It is the in-process substitute for a
// collector: the integration tier proves the real logs pipeline without starting
// any telemetry infrastructure.
type LogCapture struct {
	inner *logbridge.Capture
}

// Records returns a snapshot of every exported record.
func (c *LogCapture) Records() []CapturedLogRecord {
	captured := c.inner.Records()
	records := make([]CapturedLogRecord, 0, len(captured))
	for _, record := range captured {
		records = append(records, CapturedLogRecord{
			Timestamp:    record.Timestamp,
			Severity:     record.Severity,
			SeverityText: record.SeverityText,
			Body:         record.Body,
			Attributes:   maps.Clone(record.Attributes),
		})
	}
	return records
}

// Reset discards every recorded record.
func (c *LogCapture) Reset() { c.inner.Reset() }

// NewRecordingLogExporter builds an in-memory logs exporter and the capture its
// records land in.
func NewRecordingLogExporter() (LogExporter, *LogCapture) {
	exporter, capture := logbridge.NewRecordingExporter()
	return LogExporter{inner: exporter}, &LogCapture{inner: capture}
}

// LogAttributeValueString exercises the contained logs-value bridge and returns
// its canonical representation. It accepts only the stable v1 attribute type,
// so tests and diagnostics can verify conversion without exposing any pre-1.0
// logs SDK type in this module's public surface.
func LogAttributeValueString(value attribute.Value) string {
	return logbridge.Value(value).String()
}
