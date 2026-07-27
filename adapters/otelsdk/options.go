package otelsdk

import (
	"context"
	"io"
	"os"

	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
	"github.com/AtomiCloud/diene.go-otel/lib/otel"
	sdkmetric "go.opentelemetry.io/otel/sdk/metric"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
)

// ExporterKind names which exporter a factory is asked to build.
type ExporterKind string

const (
	// ExporterConsole is the stdout exporter.
	ExporterConsole ExporterKind = "console"
	// ExporterOtlp is the OTLP http/protobuf exporter.
	ExporterOtlp ExporterKind = "otlp"
)

// String returns the portable wire name of k.
func (k ExporterKind) String() string { return string(k) }

// SpanExporterFactory builds one span exporter. Settings carries the resolved
// OTLP wiring, whose nil fields mean "pass no option so the SDK reads its own
// environment variable".
type SpanExporterFactory func(
	ctx context.Context,
	kind ExporterKind,
	settings otel.OtlpSettings,
) (sdktrace.SpanExporter, error)

// MetricExporterFactory builds one metric exporter.
type MetricExporterFactory func(
	ctx context.Context,
	kind ExporterKind,
	settings otel.OtlpSettings,
) (sdkmetric.Exporter, error)

// LogExporterFactory builds one log exporter. It returns the OPAQUE
// [LogExporter] handle so the pre-1.0 logs SDK types never reach this module's
// public surface.
type LogExporterFactory func(
	ctx context.Context,
	kind ExporterKind,
	settings otel.OtlpSettings,
) (LogExporter, error)

// Options is the resolved construction input of a [Runtime].
type Options struct {
	// System is the environment seam every OTEL_* decision is read through.
	System interfaces.System
	// LogWriter receives console log output.
	LogWriter io.Writer
	// LoggerSink, when set, OWNS the logs signal and suppresses its pipeline.
	LoggerSink interfaces.LoggerSink
	// MetricsCollector, when set, OWNS the metrics signal.
	MetricsCollector interfaces.MetricsCollector
	// TraceEmitter, when set, OWNS the traces signal.
	TraceEmitter otel.TraceEmitter
	// SpanExporters builds span exporters.
	SpanExporters SpanExporterFactory
	// MetricExporters builds metric exporters.
	MetricExporters MetricExporterFactory
	// LogExporters builds log exporters.
	LogExporters LogExporterFactory
	// GlobalRegistration installs the built providers as the process-wide
	// OpenTelemetry providers. It defaults to false: a library must never hijack
	// a consumer's global state, so an application opts in explicitly at boot.
	GlobalRegistration bool
	// Context is the context trace correlation is read from by the plain
	// [interfaces.LoggerSink] seam, which carries no context parameter.
	Context context.Context
}

// Option customizes [Runtime] construction.
type Option func(*Options) error

// DefaultOptions returns the construction defaults: the real process
// environment, stdout console output, SDK-backed exporters, no global
// registration, and no injected seam.
func DefaultOptions() Options {
	return Options{
		System:             NewSystem(),
		LogWriter:          os.Stdout,
		SpanExporters:      DefaultSpanExporterFactory,
		MetricExporters:    DefaultMetricExporterFactory,
		LogExporters:       DefaultLogExporterFactory,
		GlobalRegistration: false,
		Context:            context.Background(),
	}
}

// WithSystem overrides the environment seam, which is how tests make every
// OTEL_* decision deterministic without mutating the process environment.
func WithSystem(system interfaces.System) Option {
	return func(options *Options) error {
		if system == nil {
			return otel.NewFault(otel.FaultEnvironmentUnavailable, "Environment unavailable",
				"WithSystem requires a non-nil System seam", otel.FaultStatusUnavailable)
		}
		options.System = system
		return nil
	}
}

// WithLogWriter overrides where console log output is written.
func WithLogWriter(writer io.Writer) Option {
	return func(options *Options) error {
		if writer == nil {
			return otel.NewFault(otel.FaultConfigInvalid, "Invalid telemetry option",
				"WithLogWriter requires a non-nil writer", otel.FaultStatusInvalidInput)
		}
		options.LogWriter = writer
		return nil
	}
}

// WithLoggerSink injects a seam that OWNS the logs signal. Its pipeline is then
// never built and the accessor returns the injected sink.
func WithLoggerSink(sink interfaces.LoggerSink) Option {
	return func(options *Options) error {
		options.LoggerSink = sink
		return nil
	}
}

// WithMetricsCollector injects a seam that OWNS the metrics signal.
func WithMetricsCollector(collector interfaces.MetricsCollector) Option {
	return func(options *Options) error {
		options.MetricsCollector = collector
		return nil
	}
}

// WithTraceEmitter injects a seam that OWNS the traces signal.
func WithTraceEmitter(emitter otel.TraceEmitter) Option {
	return func(options *Options) error {
		options.TraceEmitter = emitter
		return nil
	}
}

// WithSpanExporterFactory overrides span exporter construction.
func WithSpanExporterFactory(factory SpanExporterFactory) Option {
	return func(options *Options) error {
		if factory == nil {
			return otel.NewFault(otel.FaultConfigInvalid, "Invalid telemetry option",
				"WithSpanExporterFactory requires a non-nil factory", otel.FaultStatusInvalidInput)
		}
		options.SpanExporters = factory
		return nil
	}
}

// WithMetricExporterFactory overrides metric exporter construction.
func WithMetricExporterFactory(factory MetricExporterFactory) Option {
	return func(options *Options) error {
		if factory == nil {
			return otel.NewFault(otel.FaultConfigInvalid, "Invalid telemetry option",
				"WithMetricExporterFactory requires a non-nil factory", otel.FaultStatusInvalidInput)
		}
		options.MetricExporters = factory
		return nil
	}
}

// WithLogExporterFactory overrides log exporter construction.
func WithLogExporterFactory(factory LogExporterFactory) Option {
	return func(options *Options) error {
		if factory == nil {
			return otel.NewFault(otel.FaultConfigInvalid, "Invalid telemetry option",
				"WithLogExporterFactory requires a non-nil factory", otel.FaultStatusInvalidInput)
		}
		options.LogExporters = factory
		return nil
	}
}

// WithGlobalRegistration installs the built providers as the process-wide
// OpenTelemetry providers. Applications opt in at boot; libraries never do.
func WithGlobalRegistration(enabled bool) Option {
	return func(options *Options) error {
		options.GlobalRegistration = enabled
		return nil
	}
}

// ResolveOptions applies opts on top of [DefaultOptions], failing on the first
// rejected option.
func ResolveOptions(opts ...Option) (Options, error) {
	options := DefaultOptions()
	for _, apply := range opts {
		if apply == nil {
			continue
		}
		if err := apply(&options); err != nil {
			return Options{}, otel.NormalizeFault(err)
		}
	}
	return options, nil
}
