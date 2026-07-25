// Package logbridge contains every dependency on the pre-1.0 OpenTelemetry logs
// modules.
//
// The logs signal of the Go SDK is still a v0 module, so naming its types in this
// library's public surface would turn a v0 breaking change into a breaking change
// of this v1 module. Confining them to one internal package keeps the containment
// checkable — no exported signature of adapters/otelsdk names go.opentelemetry.io
// otel/log or sdk/log — while leaving this package's own surface exported and
// cohesive rather than a pile of private helpers.
package logbridge

import (
	"context"
	"io"
	"maps"
	"slices"
	"sync"
	"time"

	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlplog/otlploghttp"
	"go.opentelemetry.io/otel/exporters/stdout/stdoutlog"
	otellog "go.opentelemetry.io/otel/log"
	logglobal "go.opentelemetry.io/otel/log/global"
	sdklog "go.opentelemetry.io/otel/sdk/log"
	"go.opentelemetry.io/otel/sdk/resource"
)

// Severity numbers of the OpenTelemetry logs data model, exposed as plain ints so
// callers never name the v0 severity type.
const (
	// SeverityUndefined marks a level outside the portable vocabulary.
	SeverityUndefined = int(otellog.SeverityUndefined)
	// SeverityTrace is the most detailed diagnostic severity.
	SeverityTrace = int(otellog.SeverityTrace)
	// SeverityDebug is the development diagnostic severity.
	SeverityDebug = int(otellog.SeverityDebug)
	// SeverityInfo is the normal-progress severity.
	SeverityInfo = int(otellog.SeverityInfo)
	// SeverityWarn is the recoverable-abnormal severity.
	SeverityWarn = int(otellog.SeverityWarn)
	// SeverityError is the failed-operation severity.
	SeverityError = int(otellog.SeverityError)
	// SeverityFatal is the unrecoverable severity.
	SeverityFatal = int(otellog.SeverityFatal)
)

// Payload is one log record in engine-owned terms, using only the v1-stable
// attribute type.
type Payload struct {
	// Timestamp is when the event occurred.
	Timestamp time.Time
	// Severity is the numeric OpenTelemetry severity.
	Severity int
	// SeverityText is the portable level name.
	SeverityText string
	// Body is the log message.
	Body string
	// Attributes are the record's attributes.
	Attributes []attribute.KeyValue
}

// CapturedRecord is one exported log record, recorded by a [Capture].
type CapturedRecord struct {
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

// Capture records everything a recording exporter exports. It is the in-process
// substitute for a collector, so the real logs pipeline is provable without
// starting any telemetry infrastructure.
type Capture struct {
	mutex   sync.Mutex
	records []CapturedRecord
}

// Records returns a snapshot of every exported record.
func (c *Capture) Records() []CapturedRecord {
	c.mutex.Lock()
	defer c.mutex.Unlock()
	records := slices.Clone(c.records)
	for index := range records {
		records[index].Attributes = maps.Clone(records[index].Attributes)
	}
	return records
}

// Reset discards every recorded record.
func (c *Capture) Reset() {
	c.mutex.Lock()
	defer c.mutex.Unlock()
	c.records = nil
}

// Append records one exported log record.
func (c *Capture) Append(record CapturedRecord) {
	c.mutex.Lock()
	defer c.mutex.Unlock()
	c.records = append(c.records, record)
}

// Exporter is an opaque handle to a logs exporter.
type Exporter struct {
	exporter sdklog.Exporter
}

// Defined reports whether the handle carries an exporter.
func (e Exporter) Defined() bool { return e.exporter != nil }

// NewConsoleExporter builds the stdout logs exporter. A nil writer keeps the
// exporter's own default destination.
func NewConsoleExporter(writer io.Writer) (Exporter, error) {
	options := []stdoutlog.Option{}
	if writer != nil {
		options = append(options, stdoutlog.WithWriter(writer))
	}
	exporter, err := stdoutlog.New(options...)
	return Exporter{exporter: exporter}, err
}

// NewOtlpExporter builds the OTLP http/protobuf logs exporter. A nil setting is
// deliberately left unset so the exporter reads its own OTEL_* variable rather
// than being overridden by an explicit option.
func NewOtlpExporter(
	ctx context.Context,
	url *string,
	headers map[string]string,
	timeout *time.Duration,
) (Exporter, error) {
	options := []otlploghttp.Option{}
	if url != nil {
		options = append(options, otlploghttp.WithEndpointURL(*url))
	}
	if headers != nil {
		options = append(options, otlploghttp.WithHeaders(headers))
	}
	if timeout != nil {
		options = append(options, otlploghttp.WithTimeout(*timeout))
	}
	exporter, err := otlploghttp.New(ctx, options...)
	return Exporter{exporter: exporter}, err
}

// NewRecordingExporter builds an in-memory logs exporter and the capture its
// records land in.
func NewRecordingExporter() (Exporter, *Capture) {
	capture := &Capture{}
	return Exporter{exporter: &recordingExporter{capture: capture}}, capture
}

// Provider is an opaque handle to a logs pipeline.
type Provider struct {
	provider *sdklog.LoggerProvider
	logger   otellog.Logger
}

// NewProvider builds a logs pipeline exporting through exporter, tagged with res
// and scoped to scopeName.
func NewProvider(exporter Exporter, res *resource.Resource, scopeName string) *Provider {
	options := []sdklog.LoggerProviderOption{
		sdklog.WithProcessor(sdklog.NewSimpleProcessor(exporter.exporter)),
	}
	if res != nil {
		options = append(options, sdklog.WithResource(res))
	}
	provider := sdklog.NewLoggerProvider(options...)
	return &Provider{provider: provider, logger: provider.Logger(scopeName)}
}

// Emit delivers payload through the pipeline.
func (p *Provider) Emit(ctx context.Context, payload Payload) {
	record := otellog.Record{}
	record.SetTimestamp(payload.Timestamp)
	record.SetSeverity(otellog.Severity(payload.Severity))
	record.SetSeverityText(payload.SeverityText)
	record.SetBody(otellog.StringValue(payload.Body))
	record.AddAttributes(KeyValues(payload.Attributes)...)
	p.logger.Emit(ctx, record)
}

// ForceFlush exports every buffered record.
func (p *Provider) ForceFlush(ctx context.Context) error { return p.provider.ForceFlush(ctx) }

// Shutdown stops the pipeline.
func (p *Provider) Shutdown(ctx context.Context) error { return p.provider.Shutdown(ctx) }

// RegisterGlobal installs this provider as the process-wide logs provider. The
// operation lives in this containment package so the experimental logs API
// never appears in the public otelsdk surface.
func (p *Provider) RegisterGlobal() { logglobal.SetLoggerProvider(p.provider) }

// KeyValues bridges v1-stable attributes onto the logs key-value type.
func KeyValues(attributes []attribute.KeyValue) []otellog.KeyValue {
	converted := make([]otellog.KeyValue, 0, len(attributes))
	for _, keyValue := range attributes {
		converted = append(converted, otellog.KeyValue{
			Key:   string(keyValue.Key),
			Value: Value(keyValue.Value),
		})
	}
	return converted
}

// Value bridges one v1-stable attribute value onto a log value. Arrays are
// preserved as log slice values rather than stringified, so an array attribute
// survives the pipeline with its structure intact.
func Value(value attribute.Value) (converted otellog.Value) {
	converted = otellog.StringValue(value.String())
	switch value.Type() {
	case attribute.BOOL:
		converted = otellog.BoolValue(value.AsBool())
	case attribute.INT64:
		converted = otellog.Int64Value(value.AsInt64())
	case attribute.FLOAT64:
		converted = otellog.Float64Value(value.AsFloat64())
	case attribute.STRING:
		converted = otellog.StringValue(value.AsString())
	case attribute.BOOLSLICE:
		converted = SliceValue(value.AsBoolSlice(), otellog.BoolValue)
	case attribute.INT64SLICE:
		converted = SliceValue(value.AsInt64Slice(), otellog.Int64Value)
	case attribute.FLOAT64SLICE:
		converted = SliceValue(value.AsFloat64Slice(), otellog.Float64Value)
	case attribute.STRINGSLICE:
		converted = SliceValue(value.AsStringSlice(), otellog.StringValue)
	case attribute.EMPTY, attribute.BYTESLICE, attribute.SLICE:
		// Other kinds are unreachable from the portable attribute domain, which
		// otel.ValidAttributeValue restricts to the four scalars and their
		// homogeneous arrays; render defensively rather than dropping data.
		converted = otellog.StringValue(value.String())
	default:
		// Future attribute kinds retain the same defensive string initialized
		// above instead of being silently dropped.
	}
	return converted
}

// SliceValue converts a homogeneous slice into a log slice value using convert.
func SliceValue[Member any](members []Member, convert func(Member) otellog.Value) otellog.Value {
	values := make([]otellog.Value, 0, len(members))
	for _, member := range members {
		values = append(values, convert(member))
	}
	return otellog.SliceValue(values...)
}

type recordingExporter struct {
	capture *Capture
}

func (e *recordingExporter) Export(_ context.Context, records []sdklog.Record) error {
	for index := range records {
		record := records[index]
		attributes := map[string]string{}
		record.WalkAttributes(func(keyValue otellog.KeyValue) bool {
			attributes[keyValue.Key] = keyValue.Value.String()
			return true
		})
		e.capture.Append(CapturedRecord{
			Timestamp:    record.Timestamp(),
			Severity:     int(record.Severity()),
			SeverityText: record.SeverityText(),
			Body:         record.Body().String(),
			Attributes:   attributes,
		})
	}
	return nil
}

func (*recordingExporter) Shutdown(ctx context.Context) error { return ctx.Err() }

func (*recordingExporter) ForceFlush(ctx context.Context) error { return ctx.Err() }
