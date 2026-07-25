package otelsdk

import (
	"context"
	"errors"
	"maps"
	"slices"
	"sync"

	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
	"github.com/AtomiCloud/diene.go-otel/lib/otel"
	otelapi "go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/metric"
	metricnoop "go.opentelemetry.io/otel/metric/noop"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/trace"
	"go.opentelemetry.io/otel/trace/noop"

	sdkmetric "go.opentelemetry.io/otel/sdk/metric"
)

// ActiveSignals reports which signals actually export telemetry.
//
// A signal is inactive when its pipeline is disabled, when no exporter is
// selected, when OTEL_SDK_DISABLED is set, or when an injected seam owns it. This
// is on the public surface because "configured" and "exporting" are different
// questions, and a consumer's boot log should be able to state which is true.
type ActiveSignals struct {
	// Logs reports whether logs are exported.
	Logs bool
	// Metrics reports whether metrics are exported.
	Metrics bool
	// Traces reports whether traces are exported.
	Traces bool
}

// NewResource builds the OpenTelemetry resource carrying the mapped service-tree
// attributes.
func NewResource(attributes map[string]string) *resource.Resource {
	keyValues := make([]attribute.KeyValue, 0, len(attributes))
	for name, value := range attributes {
		keyValues = append(keyValues, attribute.String(name, value))
	}
	return resource.NewWithAttributes(resource.Default().SchemaURL(), keyValues...)
}

// Runtime is the wired telemetry engine: the three emission seams, their SDK
// handles, and the lifecycle that flushes and shuts them down.
type Runtime struct {
	config             otel.Config
	identity           otel.AppIdentity
	resource           *resource.Resource
	resourceAttributes map[string]string
	active             ActiveSignals
	loggerSink         interfaces.LoggerSink
	metricsCollector   interfaces.MetricsCollector
	traceEmitter       otel.TraceEmitter
	ownedLogger        *LoggerSink
	ownedMetrics       *MetricsCollector
	ownedTraces        *TraceEmitter
	tracer             trace.Tracer
	meter              metric.Meter
	shutdownOnce       sync.Once
	shutdownErr        error
}

// New builds a telemetry runtime from the canonical configuration block.
//
// Construction order is deliberate. The block and identity are validated first,
// then OTEL_SDK_DISABLED and the per-signal exporter selections are resolved, and
// only then is any SDK object built. An injected seam OWNS its signal: that
// signal's exporter, processor, and provider are never constructed, so a test
// that injects a mock cannot accidentally start a real pipeline.
func New(
	ctx context.Context,
	config otel.Config,
	identity otel.AppIdentity,
	opts ...Option,
) (*Runtime, error) {
	if err := config.Validate(); err != nil {
		return nil, err
	}
	options, optionsErr := ResolveOptions(opts...)
	if optionsErr != nil {
		return nil, optionsErr
	}
	if ctx == nil {
		ctx = context.Background()
	}
	attributes, attributesErr := otel.ResolvedResourceAttributes(identity, options.System)
	if attributesErr != nil {
		return nil, attributesErr
	}
	disabled, disabledErr := otel.SDKDisabled(options.System)
	if disabledErr != nil {
		return nil, disabledErr
	}
	selections := DisabledSelections()
	seamSignals := map[otel.Signal]struct{}{}
	if !disabled {
		resolved, selectionsErr := SignalSelections(config, options.System)
		if selectionsErr != nil {
			return nil, selectionsErr
		}
		selections = resolved
		if config.Logs.Enabled {
			seamSignals[otel.SignalLogs] = struct{}{}
		}
		if config.Metrics.Enabled {
			seamSignals[otel.SignalMetrics] = struct{}{}
		}
		if config.Traces.Enabled {
			seamSignals[otel.SignalTraces] = struct{}{}
		}
	}

	app := identity.Trimmed()
	scopeName := app.Service
	res := NewResource(attributes)
	runtime := &Runtime{
		config:             config,
		identity:           app,
		resource:           res,
		resourceAttributes: attributes,
	}

	if buildErr := runtime.BuildLogs(ctx, config, selections, options, res, scopeName, seamSignals); buildErr != nil {
		return nil, buildErr
	}
	if buildErr := runtime.BuildMetrics(ctx, config, selections, options, res, scopeName, seamSignals); buildErr != nil {
		return nil, errors.Join(buildErr, runtime.Shutdown(ctx))
	}
	if buildErr := runtime.BuildTraces(ctx, config, selections, options, res, scopeName, seamSignals); buildErr != nil {
		return nil, errors.Join(buildErr, runtime.Shutdown(ctx))
	}
	if options.GlobalRegistration {
		runtime.Register()
	}
	return runtime, nil
}

// DisabledSelections returns the selection set of a fully disabled SDK: no signal
// exports anything. It is what OTEL_SDK_DISABLED resolves to.
func DisabledSelections() map[otel.Signal]otel.Selection {
	return map[otel.Signal]otel.Selection{
		otel.SignalLogs:    {},
		otel.SignalMetrics: {},
		otel.SignalTraces:  {},
	}
}

// SignalSelections resolves the exporter selection of all three signals, folding
// in each signal's `enabled` flag and its OTEL_*_EXPORTER override. A disabled SDK
// is expressed by [DisabledSelections] instead of a flag on this function.
func SignalSelections(
	config otel.Config,
	system interfaces.System,
) (map[otel.Signal]otel.Selection, error) {
	selections := DisabledSelections()
	sources := map[otel.Signal]struct {
		enabled  bool
		exporter otel.ExporterConfig
	}{
		otel.SignalLogs:    {enabled: config.Logs.Enabled, exporter: config.Logs.Exporter},
		otel.SignalMetrics: {enabled: config.Metrics.Enabled, exporter: config.Metrics.Exporter},
		otel.SignalTraces:  {enabled: config.Traces.Enabled, exporter: config.Traces.Exporter},
	}
	for _, signal := range otel.Signals() {
		source := sources[signal]
		if !source.enabled {
			continue
		}
		selection, err := otel.ExporterSelection(source.exporter, signal, system)
		if err != nil {
			return nil, err
		}
		selections[signal] = selection
	}
	return selections, nil
}

// Config returns the validated block this runtime was built from.
func (r *Runtime) Config() otel.Config { return r.config }

// Identity returns the trimmed service-tree identity.
func (r *Runtime) Identity() otel.AppIdentity { return r.identity }

// Resource returns the OpenTelemetry resource.
func (r *Runtime) Resource() *resource.Resource { return r.resource }

// ResourceAttributes returns the resolved resource attributes.
func (r *Runtime) ResourceAttributes() map[string]string { return maps.Clone(r.resourceAttributes) }

// Active reports which signals export telemetry.
func (r *Runtime) Active() ActiveSignals { return r.active }

// LoggerSink returns the logs seam.
func (r *Runtime) LoggerSink() interfaces.LoggerSink { return r.loggerSink }

// MetricsCollector returns the metrics seam.
func (r *Runtime) MetricsCollector() interfaces.MetricsCollector { return r.metricsCollector }

// TraceEmitter returns the traces seam.
func (r *Runtime) TraceEmitter() otel.TraceEmitter { return r.traceEmitter }

// Tracer returns the tracer applications create their own spans with.
func (r *Runtime) Tracer() trace.Tracer { return r.tracer }

// Meter returns the meter applications create their own instruments with.
func (r *Runtime) Meter() metric.Meter { return r.meter }

// LoggerSinkContext returns a logs seam bound to ctx, so its records carry that
// context's trace correlation. When an injected seam owns the logs signal, the
// injected seam is returned unchanged.
func (r *Runtime) LoggerSinkContext(ctx context.Context) interfaces.LoggerSink {
	if r.ownedLogger == nil {
		return r.loggerSink
	}
	return r.ownedLogger.WithContext(ctx)
}

// Flush exports everything buffered by the pipelines this runtime owns. An
// injected seam owns its own buffering, so it is never flushed here.
func (r *Runtime) Flush(ctx context.Context) error {
	failures := []error{}
	if r.ownedLogger != nil {
		failures = append(failures, r.ownedLogger.Flush(ctx))
	}
	if r.ownedMetrics != nil {
		failures = append(failures, r.ownedMetrics.Flush(ctx))
	}
	if r.ownedTraces != nil {
		failures = append(failures, r.ownedTraces.Flush(ctx))
	}
	return errors.Join(failures...)
}

// Shutdown flushes and then stops every pipeline this runtime owns. It is
// idempotent: repeated calls return the first outcome, so a deferred shutdown and
// an explicit one cannot double-close a provider.
func (r *Runtime) Shutdown(ctx context.Context) error {
	r.shutdownOnce.Do(func() {
		failures := []error{r.Flush(ctx)}
		if r.ownedLogger != nil {
			failures = append(failures, r.ownedLogger.Shutdown(ctx))
		}
		if r.ownedMetrics != nil {
			failures = append(failures, r.ownedMetrics.Shutdown(ctx))
		}
		if r.ownedTraces != nil {
			failures = append(failures, r.ownedTraces.Shutdown(ctx))
		}
		r.shutdownErr = errors.Join(failures...)
	})
	return r.shutdownErr
}

// BuildLogs wires the logs signal. An injected sink OWNS the signal, so no
// exporter or pipeline is built for it; otherwise a console and/or OTLP path is
// built from the resolved selection.
func (r *Runtime) BuildLogs(
	ctx context.Context,
	config otel.Config,
	selections map[otel.Signal]otel.Selection,
	options Options,
	res *resource.Resource,
	scopeName string,
	seamSignals map[otel.Signal]struct{},
) error {
	selection := selections[otel.SignalLogs]
	_, seamEnabled := seamSignals[otel.SignalLogs]
	if seamEnabled && options.LoggerSink != nil {
		r.loggerSink = options.LoggerSink
		r.active.Logs = false
		return nil
	}
	exporter := LogExporter{}
	if selection.Otlp {
		settings, settingsErr := otel.OtlpExporterSettings(config.Logs.Exporter.Otlp, otel.SignalLogs, options.System)
		if settingsErr != nil {
			return settingsErr
		}
		built, buildErr := options.LogExporters(ctx, ExporterOtlp, settings)
		if buildErr != nil {
			return otel.NormalizeFault(buildErr)
		}
		exporter = built
	}
	sink := NewLoggerSink(options.Context, options.LogWriter, r.resourceAttributes,
		selection.Console, exporter, res, scopeName)
	r.ownedLogger = sink
	r.loggerSink = sink
	r.active.Logs = sink.Active()
	return nil
}

// BuildMetrics wires the metrics signal. An injected collector OWNS the signal;
// a selection with no exporter yields a provider-free collector over a no-op
// meter, which validates samples without exporting them.
func (r *Runtime) BuildMetrics(
	ctx context.Context,
	config otel.Config,
	selections map[otel.Signal]otel.Selection,
	options Options,
	res *resource.Resource,
	scopeName string,
	seamSignals map[otel.Signal]struct{},
) error {
	selection := selections[otel.SignalMetrics]
	_, seamEnabled := seamSignals[otel.SignalMetrics]
	if seamEnabled && options.MetricsCollector != nil {
		r.metricsCollector = options.MetricsCollector
		r.meter = metricnoop.NewMeterProvider().Meter(scopeName)
		r.active.Metrics = false
		return nil
	}
	if !selection.Any() {
		meter := metricnoop.NewMeterProvider().Meter(scopeName)
		collector := NewMetricsCollector(meter, nil)
		r.ownedMetrics = collector
		r.metricsCollector = collector
		r.meter = meter
		return nil
	}
	interval, intervalErr := otel.ParseFixedDuration(config.Metrics.Interval)
	if intervalErr != nil {
		return intervalErr
	}
	readers := []sdkmetric.Option{sdkmetric.WithResource(res)}
	createdExporters := []sdkmetric.Exporter{}
	cleanupExporters := func(constructionErr error) error {
		failures := []error{constructionErr}
		for _, exporter := range slices.Backward(createdExporters) {
			failures = append(failures, exporter.Shutdown(ctx))
		}
		return errors.Join(failures...)
	}
	for _, kind := range SelectedKinds(selection) {
		settings := otel.OtlpSettings{}
		if kind == ExporterOtlp {
			resolved, settingsErr := otel.OtlpExporterSettings(
				config.Metrics.Exporter.Otlp, otel.SignalMetrics, options.System,
			)
			if settingsErr != nil {
				return cleanupExporters(settingsErr)
			}
			settings = resolved
		}
		exporter, exporterErr := options.MetricExporters(ctx, kind, settings)
		if exporterErr != nil {
			return cleanupExporters(otel.NormalizeFault(exporterErr))
		}
		createdExporters = append(createdExporters, exporter)
		readers = append(readers, sdkmetric.WithReader(
			sdkmetric.NewPeriodicReader(exporter, sdkmetric.WithInterval(interval)),
		))
	}
	provider := sdkmetric.NewMeterProvider(readers...)
	meter := provider.Meter(scopeName)
	collector := NewMetricsCollector(meter, provider)
	r.ownedMetrics = collector
	r.metricsCollector = collector
	r.meter = meter
	r.active.Metrics = true
	return nil
}

// BuildTraces wires the traces signal. An injected emitter OWNS the signal; a
// selection with no exporter yields a provider-free emitter over a local no-op
// tracer that never consults a globally registered provider.
func (r *Runtime) BuildTraces(
	ctx context.Context,
	config otel.Config,
	selections map[otel.Signal]otel.Selection,
	options Options,
	res *resource.Resource,
	scopeName string,
	seamSignals map[otel.Signal]struct{},
) error {
	selection := selections[otel.SignalTraces]
	_, seamEnabled := seamSignals[otel.SignalTraces]
	if seamEnabled && options.TraceEmitter != nil {
		r.traceEmitter = options.TraceEmitter
		r.tracer = noop.NewTracerProvider().Tracer(scopeName)
		r.active.Traces = false
		return nil
	}
	if !selection.Any() {
		emitter := NewInactiveTraceEmitter(scopeName)
		r.ownedTraces = emitter
		r.traceEmitter = emitter
		r.tracer = noop.NewTracerProvider().Tracer(scopeName)
		return nil
	}
	providerOptions := []sdktrace.TracerProviderOption{sdktrace.WithResource(res)}
	sampler, samplerErr := NewSampler(config.Traces.Sampler, options.System)
	if samplerErr != nil {
		return samplerErr
	}
	if sampler != nil {
		providerOptions = append(providerOptions, sdktrace.WithSampler(sampler))
	}
	createdExporters := []sdktrace.SpanExporter{}
	cleanupExporters := func(constructionErr error) error {
		failures := []error{constructionErr}
		for _, exporter := range slices.Backward(createdExporters) {
			failures = append(failures, exporter.Shutdown(ctx))
		}
		return errors.Join(failures...)
	}
	for _, kind := range SelectedKinds(selection) {
		settings := otel.OtlpSettings{}
		if kind == ExporterOtlp {
			resolved, settingsErr := otel.OtlpExporterSettings(
				config.Traces.Exporter.Otlp, otel.SignalTraces, options.System,
			)
			if settingsErr != nil {
				return cleanupExporters(settingsErr)
			}
			settings = resolved
		}
		exporter, exporterErr := options.SpanExporters(ctx, kind, settings)
		if exporterErr != nil {
			return cleanupExporters(otel.NormalizeFault(exporterErr))
		}
		createdExporters = append(createdExporters, exporter)
		providerOptions = append(providerOptions, sdktrace.WithBatcher(exporter))
	}
	provider := sdktrace.NewTracerProvider(providerOptions...)
	tracer := provider.Tracer(scopeName)
	emitter := NewTraceEmitter(tracer, provider)
	r.ownedTraces = emitter
	r.traceEmitter = emitter
	r.tracer = tracer
	r.active.Traces = true
	return nil
}

// SelectedKinds returns the exporter kinds a selection asks for, in canonical order.
func SelectedKinds(selection otel.Selection) []ExporterKind {
	kinds := []ExporterKind{}
	if selection.Console {
		kinds = append(kinds, ExporterConsole)
	}
	if selection.Otlp {
		kinds = append(kinds, ExporterOtlp)
	}
	return kinds
}

// Register installs this runtime's providers as the process-wide OpenTelemetry
// providers. Applications call it at boot through [WithGlobalRegistration];
// libraries never do, because hijacking global state behind a consumer's back
// makes telemetry ownership unknowable.
func (r *Runtime) Register() {
	otelapi.SetTracerProvider(TracerProviderOf(r))
	otelapi.SetMeterProvider(MeterProviderOf(r))
	if r.ownedLogger != nil && r.ownedLogger.pipeline != nil {
		r.ownedLogger.pipeline.RegisterGlobal()
	}
}

// TracerProviderOf returns the runtime's tracer provider, or a no-op provider when
// the traces signal is inactive or owned by an injected seam.
func TracerProviderOf(r *Runtime) trace.TracerProvider {
	if r.ownedTraces != nil && r.ownedTraces.provider != nil {
		return r.ownedTraces.provider
	}
	return noop.NewTracerProvider()
}

// MeterProviderOf returns the runtime's meter provider, or a no-op provider when
// the metrics signal is inactive or owned by an injected seam.
func MeterProviderOf(r *Runtime) metric.MeterProvider {
	if r.ownedMetrics != nil && r.ownedMetrics.provider != nil {
		return r.ownedMetrics.provider
	}
	return metricnoop.NewMeterProvider()
}
