package otel

import (
	"math"
	"net/url"
	"slices"
	"strconv"
	"strings"
)

// ProtocolHTTPProtobuf is the only OTLP protocol permitted fleet-wide (R17).
const ProtocolHTTPProtobuf = "http/protobuf"

// OtlpHTTPPort is the fixed OTLP HTTP port every endpoint must declare (R17).
const OtlpHTTPPort = "4318"

// BlockKey is the frozen root key of the canonical telemetry block (C0 §3/§4).
const BlockKey = "otel"

// Canonical C0 §4 defaults. Signal pipelines are on, every exporter is OFF, and
// a landscape overlay is what flips OTLP on with an endpoint.
const (
	// DefaultExportTimeout is the default OTLP export timeout.
	DefaultExportTimeout = "PT10S"
	// DefaultMetricInterval is the default metric export interval.
	DefaultMetricInterval = "PT60S"
	// DefaultSamplerRatio is the default trace sampling ratio.
	DefaultSamplerRatio = 1.0
)

// SamplerType selects the trace sampling strategy. The vocabulary is frozen by
// C0 §4 and honored from v1.
type SamplerType string

const (
	// SamplerParentBasedTraceIDRatio respects a parent decision and otherwise samples by trace-id ratio.
	SamplerParentBasedTraceIDRatio SamplerType = "parentbased_traceidratio"
	// SamplerAlwaysOn samples every trace.
	SamplerAlwaysOn SamplerType = "always_on"
	// SamplerAlwaysOff samples no trace.
	SamplerAlwaysOff SamplerType = "always_off"
)

// String returns the portable wire name of s.
func (s SamplerType) String() string { return string(s) }

// SamplerTypes returns every sampler vocabulary member in canonical order.
func SamplerTypes() []SamplerType {
	return []SamplerType{SamplerParentBasedTraceIDRatio, SamplerAlwaysOn, SamplerAlwaysOff}
}

// ConsoleExporterConfig toggles the console (stdout) exporter of one signal.
type ConsoleExporterConfig struct {
	// Enabled turns the console exporter on. OFF by default everywhere.
	Enabled bool `json:"enabled" yaml:"enabled"`
}

// OtlpExporterConfig configures the OTLP exporter of one signal. The protocol is
// fixed fleet-wide, so the only per-landscape variables are the endpoint,
// headers, and timeout an overlay supplies.
type OtlpExporterConfig struct {
	// Enabled turns the OTLP exporter on. OFF by default; a landscape overlay flips it.
	Enabled bool `json:"enabled" yaml:"enabled"`
	// Endpoint is the collector base URL, e.g. http://collector:4318.
	Endpoint string `json:"endpoint" yaml:"endpoint"`
	// Protocol must equal [ProtocolHTTPProtobuf].
	Protocol string `json:"protocol" yaml:"protocol"`
	// Headers are extra HTTP headers sent with every export request.
	Headers map[string]string `json:"headers" yaml:"headers"`
	// Timeout is the per-export ISO 8601 duration, e.g. PT10S.
	Timeout string `json:"timeout" yaml:"timeout"`
}

// ExporterConfig is the exporter sub-shape shared by all three signals.
type ExporterConfig struct {
	// Console is the stdout exporter.
	Console ConsoleExporterConfig `json:"console" yaml:"console"`
	// Otlp is the OTLP http/protobuf exporter.
	Otlp OtlpExporterConfig `json:"otlp" yaml:"otlp"`
}

// LogsConfig configures the logs signal.
type LogsConfig struct {
	// Enabled turns the logs pipeline on.
	Enabled bool `json:"enabled" yaml:"enabled"`
	// Exporter selects the logs exporters.
	Exporter ExporterConfig `json:"exporter" yaml:"exporter"`
}

// MetricsConfig configures the metrics signal.
type MetricsConfig struct {
	// Enabled turns the metrics pipeline on.
	Enabled bool `json:"enabled" yaml:"enabled"`
	// Exporter selects the metrics exporters.
	Exporter ExporterConfig `json:"exporter" yaml:"exporter"`
	// Interval is the ISO 8601 metric export interval, e.g. PT60S.
	Interval string `json:"interval" yaml:"interval"`
}

// SamplerConfig configures trace sampling.
type SamplerConfig struct {
	// Type selects the sampling strategy.
	Type SamplerType `json:"type" yaml:"type"`
	// Ratio is the sampling probability in [0,1], used by the ratio sampler.
	Ratio float64 `json:"ratio" yaml:"ratio"`
}

// TracesConfig configures the traces signal.
type TracesConfig struct {
	// Enabled turns the traces pipeline on.
	Enabled bool `json:"enabled" yaml:"enabled"`
	// Sampler configures trace sampling.
	Sampler SamplerConfig `json:"sampler" yaml:"sampler"`
	// Exporter selects the trace exporters.
	Exporter ExporterConfig `json:"exporter" yaml:"exporter"`
}

// Config is the ONE canonical telemetry configuration block (C0 §4).
//
// The per-signal `logs`/`metrics`/`traces` keys and the per-exporter `enabled`
// booleans are frozen family-wide: they exist to kill the `logging`/`log` key
// drift and the `use`/`exporterType` enum-string drift of the seed repositories.
// This engine OWNS this block's schema ([JSONSchema]); the config library
// remains the sole merger and validator of a service's composed root schema.
type Config struct {
	// Logs configures the logs signal.
	Logs LogsConfig `json:"logs" yaml:"logs"`
	// Metrics configures the metrics signal.
	Metrics MetricsConfig `json:"metrics" yaml:"metrics"`
	// Traces configures the traces signal.
	Traces TracesConfig `json:"traces" yaml:"traces"`
}

// DefaultExporterConfig returns the C0 default exporter sub-shape: both
// exporters off, protocol fixed, no endpoint, no headers, PT10S timeout.
func DefaultExporterConfig() ExporterConfig {
	return ExporterConfig{
		Console: ConsoleExporterConfig{Enabled: false},
		Otlp: OtlpExporterConfig{
			Enabled:  false,
			Endpoint: "",
			Protocol: ProtocolHTTPProtobuf,
			Headers:  map[string]string{},
			Timeout:  DefaultExportTimeout,
		},
	}
}

// DefaultConfig returns the canonical C0 §4 default block: all three signal
// pipelines enabled, every exporter OFF, and the frozen protocol, timeout,
// interval, and sampler defaults.
func DefaultConfig() Config {
	return Config{
		Logs: LogsConfig{Enabled: true, Exporter: DefaultExporterConfig()},
		Metrics: MetricsConfig{
			Enabled:  true,
			Exporter: DefaultExporterConfig(),
			Interval: DefaultMetricInterval,
		},
		Traces: TracesConfig{
			Enabled:  true,
			Sampler:  SamplerConfig{Type: SamplerParentBasedTraceIDRatio, Ratio: DefaultSamplerRatio},
			Exporter: DefaultExporterConfig(),
		},
	}
}

// ValidateOtlpEndpoint checks that endpoint is an HTTP(S) URL declaring the
// fixed OTLP port. An empty endpoint is accepted here; requiring one for an
// ENABLED exporter is [OtlpExporterConfig.Validate]'s job.
func ValidateOtlpEndpoint(endpoint string) error {
	if endpoint == "" {
		return nil
	}
	parsed, parseErr := url.Parse(endpoint)
	if parseErr != nil {
		return WrapFault(FaultEndpointInvalid, "Invalid OTLP endpoint",
			"expected an absolute URL, got "+strconv.Quote(endpoint), FaultStatusInvalidInput, parseErr)
	}
	if (parsed.Scheme != "http" && parsed.Scheme != "https") || parsed.Hostname() == "" {
		return WrapFault(FaultEndpointInvalid, "Invalid OTLP endpoint",
			"expected an http or https URL with a host, got "+strconv.Quote(endpoint), FaultStatusInvalidInput, nil)
	}
	if parsed.Port() != OtlpHTTPPort {
		return WrapFault(FaultEndpointInvalid, "Invalid OTLP endpoint",
			"expected explicit port "+OtlpHTTPPort+", got "+strconv.Quote(endpoint), FaultStatusInvalidInput, nil)
	}
	return nil
}

// Validate reports whether the OTLP exporter block satisfies C0 §4: the fixed
// protocol, a fixed-length positive timeout, an endpoint on the fixed port, and
// a non-empty endpoint whenever the exporter is enabled.
func (c OtlpExporterConfig) Validate() error {
	if c.Protocol != ProtocolHTTPProtobuf {
		return WrapFault(FaultConfigInvalid, "Invalid telemetry configuration",
			"otlp protocol must be "+ProtocolHTTPProtobuf+", got "+strconv.Quote(c.Protocol),
			FaultStatusInvalidInput, nil)
	}
	if c.Enabled && strings.TrimSpace(c.Endpoint) == "" {
		return WrapFault(FaultConfigInvalid, "Invalid telemetry configuration",
			"an enabled otlp exporter requires an endpoint", FaultStatusInvalidInput, nil)
	}
	if endpointErr := ValidateOtlpEndpoint(c.Endpoint); endpointErr != nil {
		return endpointErr
	}
	for name := range c.Headers {
		if strings.TrimSpace(name) == "" {
			return WrapFault(FaultConfigInvalid, "Invalid telemetry configuration",
				"otlp header names must not be blank", FaultStatusInvalidInput, nil)
		}
	}
	_, timeoutErr := ParseFixedDuration(c.Timeout)
	return timeoutErr
}

// Validate reports whether the exporter sub-shape satisfies C0 §4.
func (c ExporterConfig) Validate() error { return c.Otlp.Validate() }

// Validate reports whether the sampler block satisfies C0 §4: a member of the
// frozen vocabulary and a ratio within [0,1].
func (c SamplerConfig) Validate() error {
	if !slices.Contains(SamplerTypes(), c.Type) {
		return NewFault(FaultSamplerInvalid, "Invalid trace sampler",
			"unsupported sampler type "+strconv.Quote(string(c.Type)), FaultStatusInvalidInput)
	}
	if math.IsNaN(c.Ratio) || c.Ratio < 0 || c.Ratio > 1 {
		return WrapFault(FaultSamplerInvalid, "Invalid trace sampler",
			"sampler ratio must be a finite value within [0,1], got "+
				strconv.FormatFloat(c.Ratio, 'g', -1, 64), FaultStatusInvalidInput, nil)
	}
	return nil
}

// Validate reports whether the logs block satisfies C0 §4.
func (c LogsConfig) Validate() error { return c.Exporter.Validate() }

// Validate reports whether the metrics block satisfies C0 §4, including a
// positive fixed-length export interval.
func (c MetricsConfig) Validate() error {
	if exporterErr := c.Exporter.Validate(); exporterErr != nil {
		return exporterErr
	}
	_, intervalErr := ParseFixedDuration(c.Interval)
	return intervalErr
}

// Validate reports whether the traces block satisfies C0 §4.
func (c TracesConfig) Validate() error {
	if samplerErr := c.Sampler.Validate(); samplerErr != nil {
		return samplerErr
	}
	return c.Exporter.Validate()
}

// Validate reports whether the whole canonical block satisfies C0 §4. It is
// fail-fast: the first violated invariant is returned as a problem-typed error.
func (c Config) Validate() error {
	if logsErr := c.Logs.Validate(); logsErr != nil {
		return logsErr
	}
	if metricsErr := c.Metrics.Validate(); metricsErr != nil {
		return metricsErr
	}
	return c.Traces.Validate()
}
