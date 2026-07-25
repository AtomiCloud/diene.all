package otel_test

import (
	"math"
	"reflect"
	"testing"

	"github.com/AtomiCloud/diene.go-otel/lib/otel"
)

func TestDefaultConfigMatchesC0(t *testing.T) {
	t.Parallel()

	wantExporter := otel.ExporterConfig{
		Console: otel.ConsoleExporterConfig{Enabled: false},
		Otlp: otel.OtlpExporterConfig{
			Enabled:  false,
			Endpoint: "",
			Protocol: otel.ProtocolHTTPProtobuf,
			Headers:  map[string]string{},
			Timeout:  otel.DefaultExportTimeout,
		},
	}
	want := otel.Config{
		Logs: otel.LogsConfig{Enabled: true, Exporter: wantExporter},
		Metrics: otel.MetricsConfig{
			Enabled:  true,
			Exporter: wantExporter,
			Interval: otel.DefaultMetricInterval,
		},
		Traces: otel.TracesConfig{
			Enabled: true,
			Sampler: otel.SamplerConfig{
				Type:  otel.SamplerParentBasedTraceIDRatio,
				Ratio: otel.DefaultSamplerRatio,
			},
			Exporter: wantExporter,
		},
	}
	if got := otel.DefaultExporterConfig(); !reflect.DeepEqual(got, wantExporter) {
		t.Fatalf("default exporter mismatch:\nwant %#v\ngot  %#v", wantExporter, got)
	}
	if got := otel.DefaultConfig(); !reflect.DeepEqual(got, want) {
		t.Fatalf("default config mismatch:\nwant %#v\ngot  %#v", want, got)
	}
	if err := want.Validate(); err != nil {
		t.Fatalf("default config must validate: %v", err)
	}
	if got := otel.SamplerParentBasedTraceIDRatio.String(); got != "parentbased_traceidratio" {
		t.Fatalf("unexpected sampler string %q", got)
	}
	if got := otel.SamplerTypes(); !reflect.DeepEqual(got, []otel.SamplerType{
		otel.SamplerParentBasedTraceIDRatio,
		otel.SamplerAlwaysOn,
		otel.SamplerAlwaysOff,
	}) {
		t.Fatalf("unexpected sampler vocabulary %#v", got)
	}
}

func TestOtlpEndpointValidation(t *testing.T) {
	t.Parallel()

	for _, endpoint := range append([]string{""}, otel.C0Otel.ValidEndpoints...) {
		if err := otel.ValidateOtlpEndpoint(endpoint); err != nil {
			t.Errorf("expected endpoint %q to pass: %v", endpoint, err)
		}
	}
	for _, endpoint := range append(otel.C0Otel.InvalidEndpoints,
		"http://%zz:4318", "ftp://collector:4318", "http:///missing:4318") {
		err := otel.ValidateOtlpEndpoint(endpoint)
		assertProblemID(t, err, otel.FaultEndpointInvalid)
	}
}

func TestOtlpExporterValidation(t *testing.T) {
	t.Parallel()

	valid := otel.DefaultExporterConfig().Otlp
	if err := valid.Validate(); err != nil {
		t.Fatalf("default exporter must validate: %v", err)
	}
	if err := (otel.ExporterConfig{Otlp: valid}).Validate(); err != nil {
		t.Fatalf("exporter wrapper must validate: %v", err)
	}
	if err := (otel.LogsConfig{Exporter: otel.ExporterConfig{Otlp: valid}}).Validate(); err != nil {
		t.Fatalf("logs block must validate: %v", err)
	}

	tests := []struct {
		name   string
		mutate func(*otel.OtlpExporterConfig)
		id     string
	}{
		{
			name: "protocol",
			mutate: func(config *otel.OtlpExporterConfig) {
				config.Protocol = "grpc"
			},
			id: otel.FaultConfigInvalid,
		},
		{
			name: "missing enabled endpoint",
			mutate: func(config *otel.OtlpExporterConfig) {
				config.Enabled = true
			},
			id: otel.FaultConfigInvalid,
		},
		{
			name: "wrong endpoint port",
			mutate: func(config *otel.OtlpExporterConfig) {
				config.Endpoint = "https://collector.example:4317"
			},
			id: otel.FaultEndpointInvalid,
		},
		{
			name: "blank header",
			mutate: func(config *otel.OtlpExporterConfig) {
				config.Headers = map[string]string{" ": "value"}
			},
			id: otel.FaultConfigInvalid,
		},
		{
			name: "duration",
			mutate: func(config *otel.OtlpExporterConfig) {
				config.Timeout = "P1Y"
			},
			id: otel.FaultDurationInvalid,
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			candidate := valid
			test.mutate(&candidate)
			assertProblemID(t, candidate.Validate(), test.id)
		})
	}
}

func TestSamplerValidation(t *testing.T) {
	t.Parallel()

	for _, samplerType := range otel.SamplerTypes() {
		candidate := otel.SamplerConfig{Type: samplerType, Ratio: 0.5}
		if err := candidate.Validate(); err != nil {
			t.Errorf("sampler %q must validate: %v", samplerType, err)
		}
	}
	for _, candidate := range []otel.SamplerConfig{
		{Type: "unknown", Ratio: 0.5},
		{Type: otel.SamplerAlwaysOn, Ratio: -0.1},
		{Type: otel.SamplerAlwaysOn, Ratio: 1.1},
		{Type: otel.SamplerAlwaysOn, Ratio: math.NaN()},
	} {
		assertProblemID(t, candidate.Validate(), otel.FaultSamplerInvalid)
	}
}

func TestNestedConfigValidationIsFailFast(t *testing.T) {
	t.Parallel()

	config := otel.DefaultConfig()
	config.Metrics.Exporter.Otlp.Protocol = "grpc"
	assertProblemID(t, config.Metrics.Validate(), otel.FaultConfigInvalid)

	config = otel.DefaultConfig()
	config.Metrics.Interval = "PT"
	assertProblemID(t, config.Metrics.Validate(), otel.FaultDurationInvalid)
	assertProblemID(t, config.Validate(), otel.FaultDurationInvalid)

	config = otel.DefaultConfig()
	config.Traces.Sampler.Type = "unknown"
	assertProblemID(t, config.Traces.Validate(), otel.FaultSamplerInvalid)
	assertProblemID(t, config.Validate(), otel.FaultSamplerInvalid)

	config = otel.DefaultConfig()
	config.Logs.Exporter.Otlp.Protocol = "grpc"
	assertProblemID(t, config.Validate(), otel.FaultConfigInvalid)
}
