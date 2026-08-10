package otel

import (
	"slices"
	"strconv"
	"strings"

	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
)

// Standard OTEL_* control variables this engine interprets itself.
const (
	// EnvSDKDisabled disables telemetry entirely and always wins over the block.
	EnvSDKDisabled = "OTEL_SDK_DISABLED"
	// EnvLogsExporter overrides the logs exporter selection.
	EnvLogsExporter = "OTEL_LOGS_EXPORTER"
	// EnvMetricsExporter overrides the metrics exporter selection.
	EnvMetricsExporter = "OTEL_METRICS_EXPORTER"
	// EnvTracesExporter overrides the traces exporter selection.
	EnvTracesExporter = "OTEL_TRACES_EXPORTER"
	// EnvTracesSampler is read natively by the SDK and suppresses our sampler option.
	EnvTracesSampler = "OTEL_TRACES_SAMPLER"
)

// Exporter selection vocabulary of the OTEL_*_EXPORTER variables.
const (
	// ExporterSelectionNone disables every exporter of a signal.
	ExporterSelectionNone = "none"
	// ExporterSelectionConsole selects the console exporter.
	ExporterSelectionConsole = "console"
	// ExporterSelectionOtlp selects the OTLP exporter.
	ExporterSelectionOtlp = "otlp"
)

// Signal names one telemetry signal.
type Signal string

const (
	// SignalLogs is the logs signal.
	SignalLogs Signal = "logs"
	// SignalMetrics is the metrics signal.
	SignalMetrics Signal = "metrics"
	// SignalTraces is the traces signal.
	SignalTraces Signal = "traces"
)

// String returns the portable wire name of s.
func (s Signal) String() string { return string(s) }

// Signals returns every signal in canonical order.
func Signals() []Signal { return []Signal{SignalLogs, SignalMetrics, SignalTraces} }

// Valid reports whether s is a member of the frozen signal vocabulary. Unknown
// signals are rejected at every boundary so a typo can never mint an
// `/v1/<arbitrary>` OTLP path or a bogus environment variable name.
func (s Signal) Valid() bool { return slices.Contains(Signals(), s) }

// ExporterEnvVariable returns the OTEL_*_EXPORTER variable that overrides this
// signal's exporter selection, or an empty string for an unknown signal.
func (s Signal) ExporterEnvVariable() string {
	switch s {
	case SignalLogs:
		return EnvLogsExporter
	case SignalMetrics:
		return EnvMetricsExporter
	case SignalTraces:
		return EnvTracesExporter
	default:
		return ""
	}
}

// Selection is the resolved per-exporter decision for one signal.
type Selection struct {
	// Console reports whether the console exporter is selected.
	Console bool
	// Otlp reports whether the OTLP exporter is selected.
	Otlp bool
}

// Any reports whether at least one exporter is selected. A signal with no
// selected exporter is inactive: records still validate, but no pipeline exists.
func (s Selection) Any() bool { return s.Console || s.Otlp }

// EnvValue reads one environment variable through the injected seam. A nil
// result means the variable is absent; a pointer to an empty string means it is
// present and empty (M33: a blank env value is treated as unset by [EnvHasValue]).
func EnvValue(system interfaces.System, name string) (*string, error) {
	if system == nil {
		return nil, NewFault(FaultEnvironmentUnavailable, "Environment unavailable",
			"a System seam is required to read "+name, FaultStatusUnavailable)
	}
	value, err := system.Environment(name)
	if err != nil {
		return nil, NormalizeFault(err)
	}
	return value, nil
}

// EnvHasValue reports whether name is present with a non-blank value. Blank means
// unset (M33), which is what makes an empty override fall back to the block.
func EnvHasValue(system interfaces.System, name string) (bool, error) {
	value, err := EnvValue(system, name)
	if err != nil {
		return false, err
	}
	return value != nil && strings.TrimSpace(*value) != "", nil
}

// SDKDisabled reports whether OTEL_SDK_DISABLED requests a fully disabled SDK.
//
// The pinned OpenTelemetry Go SDK does NOT implement this variable, so this
// engine honors it: per C0 §4 it always wins over otel.<signal>.enabled=true.
func SDKDisabled(system interfaces.System) (bool, error) {
	value, err := EnvValue(system, EnvSDKDisabled)
	if err != nil {
		return false, err
	}
	if value == nil {
		return false, nil
	}
	return strings.EqualFold(strings.TrimSpace(*value), "true"), nil
}

// ExporterSelection resolves which exporters a signal uses, applying the
// standard OTEL_*_EXPORTER override on top of the configured block. An absent or
// blank override keeps the block's per-exporter booleans; `none` disables both;
// otherwise the override is an exhaustive comma-separated allow list, so an
// unrecognized member simply selects nothing.
func ExporterSelection(config ExporterConfig, signal Signal, system interfaces.System) (Selection, error) {
	variable := signal.ExporterEnvVariable()
	if !signal.Valid() || variable == "" {
		return Selection{}, NewFault(FaultConfigInvalid, "Invalid telemetry signal",
			"unknown signal "+strconv.Quote(string(signal)), FaultStatusInvalidInput)
	}
	override, overrideErr := EnvValue(system, variable)
	if overrideErr != nil {
		return Selection{}, overrideErr
	}
	if override == nil || strings.TrimSpace(*override) == "" {
		return Selection{Console: config.Console.Enabled, Otlp: config.Otlp.Enabled}, nil
	}
	selection := Selection{}
	for member := range strings.SplitSeq(*override, ",") {
		switch strings.ToLower(strings.TrimSpace(member)) {
		case ExporterSelectionNone:
			return Selection{}, nil
		case ExporterSelectionConsole:
			selection.Console = true
		case ExporterSelectionOtlp:
			selection.Otlp = true
		default:
		}
	}
	return selection, nil
}
