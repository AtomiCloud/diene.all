package otel

import (
	"strconv"
	"strings"
)

// C0OtelProvenance records the source and version pins of the C0 §4 vectors, so
// a stale or hand-edited fixture is detectable rather than silently trusted.
type C0OtelProvenance struct {
	// ContractVersion is the monotonic C0 vector version.
	ContractVersion string
	// C0Section identifies the binding C0 contract section.
	C0Section string
	// C0Source identifies the repository contract source.
	C0Source string
}

// C0OtelContract is the shared, deterministic C0 §4 telemetry contract every
// conformance assertion in this module is driven from.
type C0OtelContract struct {
	// Provenance pins the contract inputs.
	Provenance C0OtelProvenance
	// SignalKeys are the frozen per-signal block keys.
	SignalKeys []string
	// ExporterKeys are the frozen per-exporter keys.
	ExporterKeys []string
	// OtlpKeys are the frozen OTLP exporter keys.
	OtlpKeys []string
	// Protocol is the fleet-wide OTLP protocol.
	Protocol string
	// OtlpPort is the fleet-wide OTLP HTTP port.
	OtlpPort string
	// DefaultTimeout is the default per-export timeout.
	DefaultTimeout string
	// DefaultInterval is the default metric export interval.
	DefaultInterval string
	// SamplerTypes is the frozen sampler vocabulary.
	SamplerTypes []string
	// DefaultSampler is the default sampler type.
	DefaultSampler string
	// DefaultRatio is the default sampling ratio.
	DefaultRatio float64
	// SemconvMapping maps each service-tree coordinate to its semantic convention.
	SemconvMapping map[string]string
	// AtomiAttributes are the raw taxonomy attribute keys.
	AtomiAttributes []string
	// HonoredEnvVars are the standard OTEL_* variables that win over the block.
	HonoredEnvVars []string
	// ValidEndpoints must be accepted by endpoint validation.
	ValidEndpoints []string
	// InvalidEndpoints must be rejected by endpoint validation.
	InvalidEndpoints []string
	// ValidDurations must convert to an exact positive duration.
	ValidDurations []string
	// InvalidDurations must be rejected by duration conversion.
	InvalidDurations []string
}

// DigestPayload deterministically serializes the vectors for stale-fixture
// detection: a silent edit changes the digest and reddens its pinned test.
func (contract C0OtelContract) DigestPayload() string {
	semconvEntries := make([]string, 0, len(contract.SemconvMapping))
	for _, coordinate := range []string{"landscape", "platform", "service", "version"} {
		semconvEntries = append(semconvEntries, coordinate+">"+contract.SemconvMapping[coordinate])
	}
	return strings.Join([]string{
		"contract=" + contract.Provenance.ContractVersion,
		"c0=" + contract.Provenance.C0Section + "|" + contract.Provenance.C0Source,
		"signals=" + strings.Join(contract.SignalKeys, ","),
		"exporters=" + strings.Join(contract.ExporterKeys, ","),
		"otlp=" + strings.Join(contract.OtlpKeys, ","),
		"protocol=" + contract.Protocol + "|" + contract.OtlpPort,
		"defaults=" + contract.DefaultTimeout + "|" + contract.DefaultInterval + "|" +
			contract.DefaultSampler + "|" + strconv.FormatFloat(contract.DefaultRatio, 'g', -1, 64),
		"samplers=" + strings.Join(contract.SamplerTypes, ","),
		"semconv=" + strings.Join(semconvEntries, ","),
		"atomi=" + strings.Join(contract.AtomiAttributes, ","),
		"env=" + strings.Join(contract.HonoredEnvVars, ","),
		"endpoints.valid=" + strings.Join(contract.ValidEndpoints, ","),
		"endpoints.invalid=" + strings.Join(contract.InvalidEndpoints, ","),
		"durations.valid=" + strings.Join(contract.ValidDurations, ","),
		"durations.invalid=" + strings.Join(contract.InvalidDurations, ","),
	}, "\n") + "\n"
}

// C0Otel is the single, version-pinned C0 §4 telemetry contract for Go consumers.
var C0Otel = C0OtelContract{
	Provenance: C0OtelProvenance{
		ContractVersion: "1",
		C0Section:       "C0 §4 Otel",
		C0Source:        "goals/c0-contracts.md",
	},
	SignalKeys:      []string{"logs", "metrics", "traces"},
	ExporterKeys:    []string{"console", "otlp"},
	OtlpKeys:        []string{"enabled", "endpoint", "protocol", "headers", "timeout"},
	Protocol:        ProtocolHTTPProtobuf,
	OtlpPort:        OtlpHTTPPort,
	DefaultTimeout:  DefaultExportTimeout,
	DefaultInterval: DefaultMetricInterval,
	SamplerTypes: []string{
		string(SamplerParentBasedTraceIDRatio),
		string(SamplerAlwaysOn),
		string(SamplerAlwaysOff),
	},
	DefaultSampler: string(SamplerParentBasedTraceIDRatio),
	DefaultRatio:   DefaultSamplerRatio,
	SemconvMapping: map[string]string{
		"landscape": "deployment.environment.name",
		"platform":  "service.namespace",
		"service":   "service.name",
		"version":   "service.version",
	},
	AtomiAttributes: []string{
		AttrAtomiLandscape,
		AttrAtomiPlatform,
		AttrAtomiService,
		AttrAtomiModule,
		AttrAtomiVersion,
	},
	HonoredEnvVars: []string{
		EnvSDKDisabled,
		EnvLogsExporter,
		EnvMetricsExporter,
		EnvTracesExporter,
		EnvTracesSampler,
		EnvExporterEndpoint,
		EnvExporterHeaders,
		EnvExporterTimeout,
		EnvResourceAttributes,
		EnvServiceName,
	},
	ValidEndpoints: []string{
		"http://collector:4318",
		"https://collector.example:4318",
		"http://collector:4318/",
		"http://collector:4318/v1/traces",
	},
	InvalidEndpoints: []string{
		"http://collector",
		"http://collector:4317",
		"grpc://collector:4318",
		"collector:4318",
		"http://:4318",
	},
	ValidDurations:   []string{"PT10S", "PT60S", "PT0.5S", "PT0,5S", "P1DT2H3M4.5S", "P1W"},
	InvalidDurations: []string{"P1Y", "P2M", "P1Y2M3DT4H5M6S", "P", "PT", "PT0S", "10 minutes", "1DT2H"},
}
