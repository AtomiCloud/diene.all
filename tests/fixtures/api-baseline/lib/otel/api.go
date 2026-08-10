package otel

import (
	"time"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
)

const (
	ProtocolHTTPProtobuf  = "http/protobuf"
	OtlpHTTPPort          = "4318"
	BlockKey              = "otel"
	DefaultExportTimeout  = "PT10S"
	DefaultMetricInterval = "PT60S"
	DefaultSamplerRatio   = 1.0
	FaultVersion          = "v1"

	EnvSDKDisabled     = "OTEL_SDK_DISABLED"
	EnvLogsExporter    = "OTEL_LOGS_EXPORTER"
	EnvMetricsExporter = "OTEL_METRICS_EXPORTER"
	EnvTracesExporter  = "OTEL_TRACES_EXPORTER"
	EnvTracesSampler   = "OTEL_TRACES_SAMPLER"

	ExporterSelectionNone    = "none"
	ExporterSelectionConsole = "console"
	ExporterSelectionOtlp    = "otlp"

	EnvExporterEndpoint = "OTEL_EXPORTER_OTLP_ENDPOINT"
	EnvExporterHeaders  = "OTEL_EXPORTER_OTLP_HEADERS"
	EnvExporterTimeout  = "OTEL_EXPORTER_OTLP_TIMEOUT"

	AttrAtomiLandscape    = "atomi.landscape"
	AttrAtomiPlatform     = "atomi.platform"
	AttrAtomiService      = "atomi.service"
	AttrAtomiModule       = "atomi.module"
	AttrAtomiVersion      = "atomi.version"
	EnvResourceAttributes = "OTEL_RESOURCE_ATTRIBUTES"
	EnvServiceName        = "OTEL_SERVICE_NAME"

	FaultConfigInvalid          = "otel-config-invalid"
	FaultEndpointInvalid        = "otel-endpoint-invalid"
	FaultDurationInvalid        = "otel-duration-invalid"
	FaultSamplerInvalid         = "otel-sampler-invalid"
	FaultIdentityInvalid        = "otel-identity-invalid"
	FaultRecordInvalid          = "otel-record-invalid"
	FaultEmitFailed             = "otel-emit-failed"
	FaultFlushFailed            = "otel-flush-failed"
	FaultShutdownFailed         = "otel-shutdown-failed"
	FaultEnvironmentUnavailable = "otel-environment-unavailable"
	FaultStatusInvalidInput     = 422
	FaultStatusUnavailable      = 503
)

var (
	AttrDeploymentEnvironmentName string
	AttrServiceNamespace          string
	AttrServiceName               string
	AttrServiceVersion            string
	C0Otel                        C0OtelContract
)

type SamplerType string

const (
	SamplerParentBasedTraceIDRatio SamplerType = "parentbased_traceidratio"
	SamplerAlwaysOn                SamplerType = "always_on"
	SamplerAlwaysOff               SamplerType = "always_off"
)

func (s SamplerType) String() string { return string(s) }
func SamplerTypes() []SamplerType    { return nil }

type ConsoleExporterConfig struct {
	Enabled bool `json:"enabled" yaml:"enabled"`
}

type OtlpExporterConfig struct {
	Enabled  bool              `json:"enabled" yaml:"enabled"`
	Endpoint string            `json:"endpoint" yaml:"endpoint"`
	Protocol string            `json:"protocol" yaml:"protocol"`
	Headers  map[string]string `json:"headers" yaml:"headers"`
	Timeout  string            `json:"timeout" yaml:"timeout"`
}

type ExporterConfig struct {
	Console ConsoleExporterConfig `json:"console" yaml:"console"`
	Otlp    OtlpExporterConfig    `json:"otlp" yaml:"otlp"`
}

type LogsConfig struct {
	Enabled  bool           `json:"enabled" yaml:"enabled"`
	Exporter ExporterConfig `json:"exporter" yaml:"exporter"`
}

type MetricsConfig struct {
	Enabled  bool           `json:"enabled" yaml:"enabled"`
	Exporter ExporterConfig `json:"exporter" yaml:"exporter"`
	Interval string         `json:"interval" yaml:"interval"`
}

type SamplerConfig struct {
	Type  SamplerType `json:"type" yaml:"type"`
	Ratio float64     `json:"ratio" yaml:"ratio"`
}

type TracesConfig struct {
	Enabled  bool           `json:"enabled" yaml:"enabled"`
	Sampler  SamplerConfig  `json:"sampler" yaml:"sampler"`
	Exporter ExporterConfig `json:"exporter" yaml:"exporter"`
}

type Config struct {
	Logs    LogsConfig    `json:"logs" yaml:"logs"`
	Metrics MetricsConfig `json:"metrics" yaml:"metrics"`
	Traces  TracesConfig  `json:"traces" yaml:"traces"`
}

func DefaultExporterConfig() ExporterConfig { return ExporterConfig{} }
func DefaultConfig() Config                 { return Config{} }
func ValidateOtlpEndpoint(string) error     { return nil }
func (OtlpExporterConfig) Validate() error  { return nil }
func (ExporterConfig) Validate() error      { return nil }
func (SamplerConfig) Validate() error       { return nil }
func (LogsConfig) Validate() error          { return nil }
func (MetricsConfig) Validate() error       { return nil }
func (TracesConfig) Validate() error        { return nil }
func (Config) Validate() error              { return nil }

type AppIdentity struct {
	Landscape string `json:"landscape" yaml:"landscape"`
	Platform  string `json:"platform" yaml:"platform"`
	Service   string `json:"service" yaml:"service"`
	Module    string `json:"module" yaml:"module"`
	Version   string `json:"version" yaml:"version"`
}

func (AppIdentity) Validate() error        { return nil }
func (a AppIdentity) Trimmed() AppIdentity { return a }

type Signal string

const (
	SignalLogs    Signal = "logs"
	SignalMetrics Signal = "metrics"
	SignalTraces  Signal = "traces"
)

func (s Signal) String() string            { return string(s) }
func Signals() []Signal                    { return nil }
func (Signal) Valid() bool                 { return false }
func (Signal) ExporterEnvVariable() string { return "" }

type Selection struct {
	Console bool
	Otlp    bool
}

func (Selection) Any() bool { return false }

func EnvValue(interfaces.System, string) (*string, error) { return nil, nil }
func EnvHasValue(interfaces.System, string) (bool, error) { return false, nil }
func SDKDisabled(interfaces.System) (bool, error)         { return false, nil }
func ExporterSelection(ExporterConfig, Signal, interfaces.System) (Selection, error) {
	return Selection{}, nil
}

type OtlpSettings struct {
	URL     *string
	Headers map[string]string
	Timeout *time.Duration
}

func SignalEnvVariable(string, Signal) string      { return "" }
func OtlpSignalURL(string, Signal) (string, error) { return "", nil }
func OtlpExporterSettings(OtlpExporterConfig, Signal, interfaces.System) (OtlpSettings, error) {
	return OtlpSettings{}, nil
}
func AnyEnvHasValue(interfaces.System, string, Signal) (bool, error) { return false, nil }

func ParseFixedDuration(string) (time.Duration, error)                      { return 0, nil }
func IsoComponentSeconds(string, map[byte]float64, string) (float64, error) { return 0, nil }

func SchemaKey() string                    { return "" }
func SamplerEnum() []any                   { return nil }
func DurationSchema(string) map[string]any { return nil }
func ExporterSchema() map[string]any       { return nil }
func SamplerSchema() map[string]any        { return nil }
func JSONSchema() map[string]any           { return nil }

func Portal() problem.ErrorPortal                              { return problem.ErrorPortal{} }
func FaultProblem(string, string, string, int) problem.Problem { return problem.Problem{} }
func NewFault(string, string, string, int) error               { return nil }
func WrapFault(string, string, string, int, error) error       { return nil }
func NormalizeFault(error) error                               { return nil }

func ResourceAttributes(AppIdentity) (map[string]string, error) { return nil, nil }
func ParseResourceAttributes(string) map[string]string          { return nil }
func ResolvedResourceAttributes(AppIdentity, interfaces.System) (map[string]string, error) {
	return nil, nil
}

func ValidLogLevel(interfaces.LogLevel) bool             { return false }
func ValidateLogRecord(interfaces.LogRecord) error       { return nil }
func ValidMetricKind(interfaces.MetricKind) bool         { return false }
func ValidateMetricRecord(interfaces.MetricRecord) error { return nil }

type TraceStatus string

const (
	TraceStatusUnset TraceStatus = "unset"
	TraceStatusOK    TraceStatus = "ok"
	TraceStatusError TraceStatus = "error"
)

func (s TraceStatus) String() string { return string(s) }
func TraceStatuses() []TraceStatus   { return nil }

type TraceEvent struct {
	Name       string
	Attributes map[string]any
}

func NewTraceEvent(string, map[string]any) TraceEvent { return TraceEvent{} }
func (TraceEvent) Clone() TraceEvent                  { return TraceEvent{} }

type TraceRecord struct {
	Timestamp     time.Time
	Name          string
	Attributes    map[string]any
	Events        []TraceEvent
	Status        TraceStatus
	StatusMessage *string
}

func NewTraceRecord(time.Time, string, map[string]any, []TraceEvent, TraceStatus, *string) TraceRecord {
	return TraceRecord{}
}
func (TraceRecord) Clone() TraceRecord        { return TraceRecord{} }
func (TraceRecord) Validate() error           { return nil }
func ValidTraceStatus(TraceStatus) bool       { return false }
func ValidateAttributes(map[string]any) error { return nil }
func ValidAttributeValue(any) bool            { return false }
func FiniteFloat(float64) bool                { return false }

type TraceEmitter interface {
	Emit(TraceRecord) error
}

type C0OtelProvenance struct {
	ContractVersion string
	C0Section       string
	C0Source        string
}

type C0OtelContract struct {
	Provenance       C0OtelProvenance
	SignalKeys       []string
	ExporterKeys     []string
	OtlpKeys         []string
	Protocol         string
	OtlpPort         string
	DefaultTimeout   string
	DefaultInterval  string
	SamplerTypes     []string
	DefaultSampler   string
	DefaultRatio     float64
	SemconvMapping   map[string]string
	AtomiAttributes  []string
	HonoredEnvVars   []string
	ValidEndpoints   []string
	InvalidEndpoints []string
	ValidDurations   []string
	InvalidDurations []string
}

func (C0OtelContract) DigestPayload() string { return "" }
