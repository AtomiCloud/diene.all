package otelsdk

import (
	"context"

	"github.com/AtomiCloud/diene.go-otel/lib/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetrichttp"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/exporters/stdout/stdoutmetric"
	"go.opentelemetry.io/otel/exporters/stdout/stdouttrace"
	sdkmetric "go.opentelemetry.io/otel/sdk/metric"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
)

// DefaultSpanExporterFactory builds the SDK's span exporters. Each nil field in
// settings is deliberately left unset so the exporter reads its own OTEL_*
// variable: an explicit option would override the operator's escape hatch.
func DefaultSpanExporterFactory(
	ctx context.Context,
	kind ExporterKind,
	settings otel.OtlpSettings,
) (sdktrace.SpanExporter, error) {
	switch kind {
	case ExporterConsole:
		exporter, err := stdouttrace.New()
		return exporter, otel.NormalizeFault(err)
	case ExporterOtlp:
		if settings.URL != nil {
			if err := otel.ValidateOtlpEndpoint(*settings.URL); err != nil {
				return nil, err
			}
		}
		options := []otlptracehttp.Option{}
		if settings.URL != nil {
			options = append(options, otlptracehttp.WithEndpointURL(*settings.URL))
		}
		if settings.Headers != nil {
			options = append(options, otlptracehttp.WithHeaders(settings.Headers))
		}
		if settings.Timeout != nil {
			options = append(options, otlptracehttp.WithTimeout(*settings.Timeout))
		}
		exporter, err := otlptracehttp.New(ctx, options...)
		return exporter, otel.NormalizeFault(err)
	default:
		return nil, UnknownExporterFault(kind)
	}
}

// DefaultMetricExporterFactory builds the SDK's metric exporters.
func DefaultMetricExporterFactory(
	ctx context.Context,
	kind ExporterKind,
	settings otel.OtlpSettings,
) (sdkmetric.Exporter, error) {
	switch kind {
	case ExporterConsole:
		exporter, err := stdoutmetric.New()
		return exporter, otel.NormalizeFault(err)
	case ExporterOtlp:
		if settings.URL != nil {
			if err := otel.ValidateOtlpEndpoint(*settings.URL); err != nil {
				return nil, err
			}
		}
		options := []otlpmetrichttp.Option{}
		if settings.URL != nil {
			options = append(options, otlpmetrichttp.WithEndpointURL(*settings.URL))
		}
		if settings.Headers != nil {
			options = append(options, otlpmetrichttp.WithHeaders(settings.Headers))
		}
		if settings.Timeout != nil {
			options = append(options, otlpmetrichttp.WithTimeout(*settings.Timeout))
		}
		exporter, err := otlpmetrichttp.New(ctx, options...)
		return exporter, otel.NormalizeFault(err)
	default:
		return nil, UnknownExporterFault(kind)
	}
}

// DefaultLogExporterFactory builds the SDK's log exporters behind the opaque
// [LogExporter] handle.
func DefaultLogExporterFactory(
	ctx context.Context,
	kind ExporterKind,
	settings otel.OtlpSettings,
) (LogExporter, error) {
	switch kind {
	case ExporterConsole:
		return NewConsoleLogExporter(nil)
	case ExporterOtlp:
		return NewOtlpLogExporter(ctx, settings)
	default:
		return LogExporter{}, UnknownExporterFault(kind)
	}
}

// UnknownExporterFault reports an exporter kind outside the frozen vocabulary.
func UnknownExporterFault(kind ExporterKind) error {
	return otel.NewFault(otel.FaultConfigInvalid, "Invalid telemetry exporter",
		"unknown exporter kind "+string(kind), otel.FaultStatusInvalidInput)
}
