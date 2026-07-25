package otelsdk_test

import (
	"bytes"
	"context"
	"errors"
	"maps"
	"reflect"
	"slices"
	"testing"

	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
	interfaceshelper "github.com/AtomiCloud/diene.go-interfaces/testhelper"
	"github.com/AtomiCloud/diene.go-otel/adapters/otelsdk"
	"github.com/AtomiCloud/diene.go-otel/lib/otel"
	"github.com/AtomiCloud/diene.go-otel/testhelper"
	sdkmetric "go.opentelemetry.io/otel/sdk/metric"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/sdk/trace/tracetest"
)

func TestDefaultRuntimeIsProviderFreeAndValidating(t *testing.T) {
	t.Parallel()

	config := otel.DefaultConfig()
	identity := testhelper.SampleIdentity()
	var nilContext context.Context
	runtime, err := otelsdk.New(
		nilContext, config, identity,
		otelsdk.WithSystem(systemWith(nil)),
		otelsdk.WithLogWriter(&bytes.Buffer{}),
	)
	if err != nil {
		t.Fatalf("build default runtime: %v", err)
	}
	if runtime.Active() != (otelsdk.ActiveSignals{}) {
		t.Fatalf("off-by-default exporters unexpectedly active: %+v", runtime.Active())
	}
	if !reflect.DeepEqual(runtime.Config(), config) || runtime.Identity() != identity || runtime.Resource() == nil {
		t.Fatal("runtime accessors do not preserve construction input")
	}
	wantAttributes, err := otel.ResourceAttributes(identity)
	if err != nil {
		t.Fatalf("map identity: %v", err)
	}
	attributes := runtime.ResourceAttributes()
	if !maps.Equal(attributes, wantAttributes) {
		t.Fatalf("resource attributes mismatch: %#v", attributes)
	}
	attributes[otel.AttrServiceName] = "mutated"
	if runtime.ResourceAttributes()[otel.AttrServiceName] == "mutated" {
		t.Fatal("resource attribute accessor aliases runtime state")
	}
	if runtime.LoggerSink() == nil || runtime.MetricsCollector() == nil || runtime.TraceEmitter() == nil ||
		runtime.Tracer() == nil || runtime.Meter() == nil || runtime.LoggerSinkContext(context.Background()) == nil {
		t.Fatal("provider-free runtime returned a nil accessor")
	}
	if err := runtime.LoggerSink().Emit(testhelper.SampleLogRecord()); err != nil {
		t.Fatalf("provider-free log validation: %v", err)
	}
	if err := runtime.MetricsCollector().Emit(testhelper.SampleMetricRecord()); err != nil {
		t.Fatalf("provider-free metric validation: %v", err)
	}
	if err := runtime.TraceEmitter().Emit(testhelper.SampleTraceRecord()); err != nil {
		t.Fatalf("provider-free trace validation: %v", err)
	}
	if err := runtime.Flush(context.Background()); err != nil {
		t.Fatalf("flush provider-free runtime: %v", err)
	}
	if err := runtime.Shutdown(context.Background()); err != nil {
		t.Fatalf("shutdown provider-free runtime: %v", err)
	}
	if err := runtime.Shutdown(context.Background()); err != nil {
		t.Fatalf("idempotent shutdown changed result: %v", err)
	}
	if otelsdk.TracerProviderOf(runtime) == nil || otelsdk.MeterProviderOf(runtime) == nil {
		t.Fatal("provider accessors must return local no-op providers")
	}
}

func TestInjectedSeamsOwnOnlyEnabledNonDisabledSignals(t *testing.T) {
	t.Parallel()

	for _, test := range []struct {
		name        string
		config      otel.Config
		environment map[string]string
		wantOwned   bool
	}{
		{name: "enabled", config: otel.DefaultConfig(), wantOwned: true},
		{
			name: "signal disabled",
			config: func() otel.Config {
				config := otel.DefaultConfig()
				config.Logs.Enabled = false
				config.Metrics.Enabled = false
				config.Traces.Enabled = false
				return config
			}(),
			wantOwned: false,
		},
		{
			name:        "SDK disabled",
			config:      otel.DefaultConfig(),
			environment: map[string]string{otel.EnvSDKDisabled: "true"},
			wantOwned:   false,
		},
	} {
		t.Run(test.name, func(t *testing.T) {
			logs := testhelper.NewInMemoryLoggerSink()
			metrics := testhelper.NewInMemoryMetricsCollector()
			traces := testhelper.NewInMemoryTraceEmitter()
			factoryCalls := 0
			runtime, err := otelsdk.New(
				context.Background(), test.config, testhelper.SampleIdentity(),
				otelsdk.WithSystem(systemWith(test.environment)),
				otelsdk.WithLoggerSink(logs),
				otelsdk.WithMetricsCollector(metrics),
				otelsdk.WithTraceEmitter(traces),
				otelsdk.WithSpanExporterFactory(func(context.Context, otelsdk.ExporterKind, otel.OtlpSettings) (sdktrace.SpanExporter, error) {
					factoryCalls++
					return tracetest.NewInMemoryExporter(), nil
				}),
			)
			if err != nil {
				t.Fatalf("build runtime: %v", err)
			}
			if factoryCalls != 0 {
				t.Fatal("injected or inactive signals built an exporter")
			}
			if (runtime.LoggerSink() == logs) != test.wantOwned ||
				(runtime.MetricsCollector() == metrics) != test.wantOwned ||
				(runtime.TraceEmitter() == traces) != test.wantOwned {
				t.Fatal("seam ownership mismatch")
			}
			if runtime.Active() != (otelsdk.ActiveSignals{}) {
				t.Fatal("injected/inactive signals must not report SDK pipelines")
			}
			if test.wantOwned && runtime.LoggerSinkContext(context.Background()) != logs {
				t.Fatal("injected logger context accessor changed the seam")
			}
			if err := runtime.LoggerSink().Emit(testhelper.SampleLogRecord()); err != nil {
				t.Fatalf("emit log: %v", err)
			}
			if err := runtime.MetricsCollector().Emit(testhelper.SampleMetricRecord()); err != nil {
				t.Fatalf("emit metric: %v", err)
			}
			if err := runtime.TraceEmitter().Emit(testhelper.SampleTraceRecord()); err != nil {
				t.Fatalf("emit trace: %v", err)
			}
			wantCount := 0
			if test.wantOwned {
				wantCount = 1
			}
			if len(logs.Records()) != wantCount || len(metrics.Records()) != wantCount || len(traces.Records()) != wantCount {
				t.Fatalf("seam emissions mismatch: %d %d %d",
					len(logs.Records()), len(metrics.Records()), len(traces.Records()))
			}
		})
	}
}

func TestRuntimeExportsAllThreeSignalsThroughInProcessFactories(t *testing.T) {
	t.Parallel()

	config := testhelper.SampleConfig()
	spanExporter := tracetest.NewInMemoryExporter()
	metricExporter := &recordingMetricExporter{}
	logExporter, logCapture := otelsdk.NewRecordingLogExporter()
	spanKinds := []otelsdk.ExporterKind{}
	metricKinds := []otelsdk.ExporterKind{}
	logKinds := []otelsdk.ExporterKind{}
	settingsBySignal := map[otel.Signal]otel.OtlpSettings{}
	runtime, err := otelsdk.New(
		context.Background(), config, testhelper.SampleIdentity(),
		otelsdk.WithSystem(systemWith(nil)),
		otelsdk.WithSpanExporterFactory(func(_ context.Context, kind otelsdk.ExporterKind,
			settings otel.OtlpSettings,
		) (sdktrace.SpanExporter, error) {
			spanKinds = append(spanKinds, kind)
			settingsBySignal[otel.SignalTraces] = settings
			return spanExporter, nil
		}),
		otelsdk.WithMetricExporterFactory(func(_ context.Context, kind otelsdk.ExporterKind,
			settings otel.OtlpSettings,
		) (sdkmetric.Exporter, error) {
			metricKinds = append(metricKinds, kind)
			settingsBySignal[otel.SignalMetrics] = settings
			return metricExporter, nil
		}),
		otelsdk.WithLogExporterFactory(func(_ context.Context, kind otelsdk.ExporterKind,
			settings otel.OtlpSettings,
		) (otelsdk.LogExporter, error) {
			logKinds = append(logKinds, kind)
			settingsBySignal[otel.SignalLogs] = settings
			return logExporter, nil
		}),
	)
	if err != nil {
		t.Fatalf("build exporting runtime: %v", err)
	}
	if runtime.Active() != (otelsdk.ActiveSignals{Logs: true, Metrics: true, Traces: true}) {
		t.Fatalf("all pipelines must be active: %+v", runtime.Active())
	}
	for signal, settings := range settingsBySignal {
		if settings.URL == nil || *settings.URL != "https://collector.example:4318/v1/"+signal.String() {
			t.Errorf("unexpected %s settings: %#v", signal, settings)
		}
	}
	if !reflect.DeepEqual(spanKinds, []otelsdk.ExporterKind{otelsdk.ExporterOtlp}) ||
		!reflect.DeepEqual(metricKinds, []otelsdk.ExporterKind{otelsdk.ExporterOtlp}) ||
		!reflect.DeepEqual(logKinds, []otelsdk.ExporterKind{otelsdk.ExporterOtlp}) {
		t.Fatalf("unexpected exporter kinds: %#v %#v %#v", spanKinds, metricKinds, logKinds)
	}
	if err := runtime.LoggerSink().Emit(testhelper.SampleLogRecord()); err != nil {
		t.Fatalf("emit log: %v", err)
	}
	if err := runtime.MetricsCollector().Emit(testhelper.SampleMetricRecord()); err != nil {
		t.Fatalf("emit metric: %v", err)
	}
	if err := runtime.TraceEmitter().Emit(testhelper.SampleTraceRecord()); err != nil {
		t.Fatalf("emit trace: %v", err)
	}
	if err := runtime.Flush(context.Background()); err != nil {
		t.Fatalf("flush exporting runtime: %v", err)
	}
	if len(logCapture.Records()) != 1 || len(spanExporter.GetSpans()) != 1 ||
		!slices.Contains(metricExporter.metricNames(), testhelper.SampleMetricRecord().Name) {
		t.Fatal("one or more real pipelines did not export")
	}
	if runtime.LoggerSinkContext(context.Background()) == runtime.LoggerSink() {
		t.Fatal("owned logger context binding returned the same sink")
	}
	if otelsdk.TracerProviderOf(runtime) == nil || otelsdk.MeterProviderOf(runtime) == nil {
		t.Fatal("active providers missing")
	}
	runtime.Register()
	if err := runtime.Shutdown(context.Background()); err != nil {
		t.Fatalf("shutdown exporting runtime: %v", err)
	}
}

func TestConsoleSelectionAndGlobalRegistration(t *testing.T) {
	t.Parallel()

	config := otel.DefaultConfig()
	config.Logs.Exporter.Console.Enabled = true
	config.Metrics.Exporter.Console.Enabled = true
	config.Traces.Exporter.Console.Enabled = true
	spanExporter := tracetest.NewInMemoryExporter()
	metricExporter := &recordingMetricExporter{}
	spanKinds := []otelsdk.ExporterKind{}
	metricKinds := []otelsdk.ExporterKind{}
	runtime, err := otelsdk.New(
		context.Background(), config, testhelper.SampleIdentity(),
		otelsdk.WithSystem(systemWith(nil)),
		otelsdk.WithLogWriter(&bytes.Buffer{}),
		otelsdk.WithGlobalRegistration(true),
		otelsdk.WithSpanExporterFactory(func(_ context.Context, kind otelsdk.ExporterKind,
			_ otel.OtlpSettings,
		) (sdktrace.SpanExporter, error) {
			spanKinds = append(spanKinds, kind)
			return spanExporter, nil
		}),
		otelsdk.WithMetricExporterFactory(func(_ context.Context, kind otelsdk.ExporterKind,
			_ otel.OtlpSettings,
		) (sdkmetric.Exporter, error) {
			metricKinds = append(metricKinds, kind)
			return metricExporter, nil
		}),
	)
	if err != nil {
		t.Fatalf("build console runtime: %v", err)
	}
	if runtime.Active() != (otelsdk.ActiveSignals{Logs: true, Metrics: true, Traces: true}) ||
		!reflect.DeepEqual(spanKinds, []otelsdk.ExporterKind{otelsdk.ExporterConsole}) ||
		!reflect.DeepEqual(metricKinds, []otelsdk.ExporterKind{otelsdk.ExporterConsole}) {
		t.Fatalf("console selection mismatch: %+v %#v %#v", runtime.Active(), spanKinds, metricKinds)
	}
	if got := otelsdk.SelectedKinds(otel.Selection{}); len(got) != 0 {
		t.Fatalf("empty selection returned kinds %#v", got)
	}
	if got := otelsdk.SelectedKinds(otel.Selection{Console: true, Otlp: true}); !reflect.DeepEqual(got, []otelsdk.ExporterKind{otelsdk.ExporterConsole, otelsdk.ExporterOtlp}) {
		t.Fatalf("selected-kind order changed: %#v", got)
	}
	if err := runtime.Shutdown(context.Background()); err != nil {
		t.Fatalf("shutdown console runtime: %v", err)
	}
}

func TestSignalSelections(t *testing.T) {
	t.Parallel()

	disabled := otelsdk.DisabledSelections()
	for _, signal := range otel.Signals() {
		if disabled[signal].Any() {
			t.Fatalf("disabled signal %q selected an exporter", signal)
		}
	}
	config := otel.DefaultConfig()
	config.Logs.Exporter.Console.Enabled = true
	config.Metrics.Enabled = false
	config.Traces.Exporter.Otlp.Enabled = true
	config.Traces.Exporter.Otlp.Endpoint = "https://collector.example:4318"
	selections, err := otelsdk.SignalSelections(config, systemWith(map[string]string{
		otel.EnvLogsExporter:   "otlp",
		otel.EnvTracesExporter: "console",
	}))
	if err != nil {
		t.Fatalf("resolve selections: %v", err)
	}
	if selections[otel.SignalLogs] != (otel.Selection{Otlp: true}) ||
		selections[otel.SignalMetrics].Any() ||
		selections[otel.SignalTraces] != (otel.Selection{Console: true}) {
		t.Fatalf("unexpected selections %#v", selections)
	}
	_, err = otelsdk.SignalSelections(otel.DefaultConfig(), nil)
	assertProblemID(t, err, otel.FaultEnvironmentUnavailable)
}

func TestRuntimeConstructionFailures(t *testing.T) {
	t.Parallel()

	identity := testhelper.SampleIdentity()
	invalidConfig := otel.DefaultConfig()
	invalidConfig.Metrics.Interval = "PT"
	_, err := otelsdk.New(context.Background(), invalidConfig, identity, otelsdk.WithSystem(systemWith(nil)))
	assertProblemID(t, err, otel.FaultDurationInvalid)

	optionCause := errors.New("option failed")
	_, err = otelsdk.New(context.Background(), otel.DefaultConfig(), identity,
		func(*otelsdk.Options) error { return optionCause })
	if !errors.Is(err, optionCause) {
		t.Fatalf("option cause lost: %v", err)
	}

	invalidIdentity := identity
	invalidIdentity.Module = ""
	_, err = otelsdk.New(context.Background(), otel.DefaultConfig(), invalidIdentity,
		otelsdk.WithSystem(systemWith(nil)))
	assertProblemID(t, err, otel.FaultIdentityInvalid)

	for failureIndex := range 4 {
		broken := interfaceshelper.NewInMemorySystem(interfaceshelper.InMemorySystemOptions{})
		for range failureIndex {
			broken.EnqueueEnvironmentResult(nil, nil)
		}
		cause := errors.New("environment failed")
		broken.EnqueueEnvironmentResult(nil, cause)
		_, err = otelsdk.New(context.Background(), otel.DefaultConfig(), identity, otelsdk.WithSystem(broken))
		if !errors.Is(err, cause) {
			t.Fatalf("environment failure %d lost: %v", failureIndex, err)
		}
	}

	factoryCause := errors.New("factory failed")
	for _, signal := range otel.Signals() {
		config := otel.DefaultConfig()
		switch signal {
		case otel.SignalLogs:
			config.Logs.Exporter.Otlp.Enabled = true
			config.Logs.Exporter.Otlp.Endpoint = "https://collector.example:4318"
		case otel.SignalMetrics:
			config.Metrics.Exporter.Otlp.Enabled = true
			config.Metrics.Exporter.Otlp.Endpoint = "https://collector.example:4318"
		case otel.SignalTraces:
			config.Traces.Exporter.Otlp.Enabled = true
			config.Traces.Exporter.Otlp.Endpoint = "https://collector.example:4318"
		default:
			t.Fatalf("unexpected signal %q", signal)
		}
		_, err = otelsdk.New(
			context.Background(), config, identity,
			otelsdk.WithSystem(systemWith(nil)),
			otelsdk.WithLogExporterFactory(func(context.Context, otelsdk.ExporterKind, otel.OtlpSettings) (otelsdk.LogExporter, error) {
				return otelsdk.LogExporter{}, factoryCause
			}),
			otelsdk.WithMetricExporterFactory(func(context.Context, otelsdk.ExporterKind, otel.OtlpSettings) (sdkmetric.Exporter, error) {
				return nil, factoryCause
			}),
			otelsdk.WithSpanExporterFactory(func(context.Context, otelsdk.ExporterKind, otel.OtlpSettings) (sdktrace.SpanExporter, error) {
				return nil, factoryCause
			}),
		)
		if !errors.Is(err, factoryCause) {
			t.Fatalf("%s factory cause lost: %v", signal, err)
		}
	}
}

func TestDirectBuildValidationFailures(t *testing.T) {
	t.Parallel()

	options := otelsdk.DefaultOptions()
	options.System = systemWith(nil)
	resource := otelsdk.NewResource(map[string]string{"service.name": "service"})
	seamSignals := map[otel.Signal]struct{}{}

	config := otel.DefaultConfig()
	config.Metrics.Interval = "PT"
	runtime := &otelsdk.Runtime{}
	err := runtime.BuildMetrics(context.Background(), config,
		map[otel.Signal]otel.Selection{otel.SignalMetrics: {Console: true}},
		options, resource, "service", seamSignals)
	assertProblemID(t, err, otel.FaultDurationInvalid)

	config = otel.DefaultConfig()
	config.Traces.Sampler.Type = "unknown"
	runtime = &otelsdk.Runtime{}
	err = runtime.BuildTraces(context.Background(), config,
		map[otel.Signal]otel.Selection{otel.SignalTraces: {Console: true}},
		options, resource, "service", seamSignals)
	assertProblemID(t, err, otel.FaultSamplerInvalid)

	brokenOptions := options
	brokenOptions.System = nil
	runtime = &otelsdk.Runtime{}
	err = runtime.BuildLogs(context.Background(), testhelper.SampleConfig(),
		map[otel.Signal]otel.Selection{otel.SignalLogs: {Otlp: true}},
		brokenOptions, resource, "service", seamSignals)
	assertProblemID(t, err, otel.FaultEnvironmentUnavailable)
	runtime = &otelsdk.Runtime{}
	err = runtime.BuildMetrics(context.Background(), testhelper.SampleConfig(),
		map[otel.Signal]otel.Selection{otel.SignalMetrics: {Otlp: true}},
		brokenOptions, resource, "service", seamSignals)
	assertProblemID(t, err, otel.FaultEnvironmentUnavailable)
	runtime = &otelsdk.Runtime{}
	err = runtime.BuildTraces(context.Background(), testhelper.SampleConfig(),
		map[otel.Signal]otel.Selection{otel.SignalTraces: {Otlp: true}},
		brokenOptions, resource, "service", seamSignals)
	assertProblemID(t, err, otel.FaultEnvironmentUnavailable)

	settingsBroken := options
	settingsSystem := interfaceshelper.NewInMemorySystem(interfaceshelper.InMemorySystemOptions{})
	settingsSystem.EnqueueEnvironmentResult(nil, nil)
	settingsSystem.EnqueueEnvironmentResult(nil, errors.New("settings environment failed"))
	settingsBroken.System = settingsSystem
	runtime = &otelsdk.Runtime{}
	err = runtime.BuildTraces(context.Background(), testhelper.SampleConfig(),
		map[otel.Signal]otel.Selection{otel.SignalTraces: {Otlp: true}},
		settingsBroken, resource, "service", seamSignals)
	if err == nil {
		t.Fatal("trace settings environment failure was ignored")
	}
}

func TestRuntimeLifecycleAggregatesProviderFailures(t *testing.T) {
	t.Parallel()

	config := otel.DefaultConfig()
	config.Metrics.Exporter.Console.Enabled = true
	config.Traces.Exporter.Console.Enabled = true
	metricCause := errors.New("metric flush failed")
	spanCause := errors.New("span export failed")
	metricExporter := &recordingMetricExporter{flushErr: metricCause}
	spanExporter := &recordingSpanExporter{exportErr: spanCause}
	runtime, err := otelsdk.New(
		context.Background(), config, testhelper.SampleIdentity(),
		otelsdk.WithSystem(systemWith(nil)),
		otelsdk.WithMetricExporterFactory(func(context.Context, otelsdk.ExporterKind, otel.OtlpSettings) (sdkmetric.Exporter, error) {
			return metricExporter, nil
		}),
		otelsdk.WithSpanExporterFactory(func(context.Context, otelsdk.ExporterKind, otel.OtlpSettings) (sdktrace.SpanExporter, error) {
			return spanExporter, nil
		}),
	)
	if err != nil {
		t.Fatalf("build failing runtime: %v", err)
	}
	if emitErr := runtime.TraceEmitter().Emit(testhelper.SampleTraceRecord()); emitErr != nil {
		t.Fatalf("queue span: %v", emitErr)
	}
	err = runtime.Flush(context.Background())
	if !errors.Is(err, metricCause) || !errors.Is(err, spanCause) {
		t.Fatalf("runtime flush did not aggregate causes: %v", err)
	}
	_ = runtime.Shutdown(context.Background())

	shutdownMetricCause := errors.New("metric shutdown failed")
	shutdownSpanCause := errors.New("span shutdown failed")
	metricExporter = &recordingMetricExporter{shutdownErr: shutdownMetricCause}
	spanExporter = &recordingSpanExporter{shutdownErr: shutdownSpanCause}
	runtime, err = otelsdk.New(
		context.Background(), config, testhelper.SampleIdentity(),
		otelsdk.WithSystem(systemWith(nil)),
		otelsdk.WithMetricExporterFactory(func(context.Context, otelsdk.ExporterKind, otel.OtlpSettings) (sdkmetric.Exporter, error) {
			return metricExporter, nil
		}),
		otelsdk.WithSpanExporterFactory(func(context.Context, otelsdk.ExporterKind, otel.OtlpSettings) (sdktrace.SpanExporter, error) {
			return spanExporter, nil
		}),
	)
	if err != nil {
		t.Fatalf("build shutdown-failing runtime: %v", err)
	}
	err = runtime.Shutdown(context.Background())
	if !errors.Is(err, shutdownMetricCause) || !errors.Is(err, shutdownSpanCause) {
		t.Fatalf("runtime shutdown did not aggregate causes: %v", err)
	}
	if second := runtime.Shutdown(context.Background()); !errors.Is(second, shutdownMetricCause) {
		t.Fatalf("idempotent shutdown did not retain outcome: %v", second)
	}
}

func TestResourceConstruction(t *testing.T) {
	t.Parallel()

	attributes := map[string]string{"service.name": "service", "atomi.module": "module"}
	resource := otelsdk.NewResource(attributes)
	got := map[string]string{}
	for _, keyValue := range resource.Attributes() {
		got[string(keyValue.Key)] = keyValue.Value.AsString()
	}
	for key, value := range attributes {
		if got[key] != value {
			t.Errorf("resource attribute %q: want %q, got %q", key, value, got[key])
		}
	}
}

var (
	_ interfaces.LoggerSink       = testhelper.NewInMemoryLoggerSink()
	_ interfaces.MetricsCollector = testhelper.NewInMemoryMetricsCollector()
)
