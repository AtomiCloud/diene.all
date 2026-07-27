package otel

import (
	"maps"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
)

// Standard OTLP exporter environment variables. When one of these carries a
// value, this engine passes NO corresponding SDK option so the SDK's own env
// handling wins — an explicit option would otherwise override the operator.
const (
	// EnvExporterEndpoint is the generic OTLP base endpoint.
	EnvExporterEndpoint = "OTEL_EXPORTER_OTLP_ENDPOINT"
	// EnvExporterHeaders is the generic OTLP header list.
	EnvExporterHeaders = "OTEL_EXPORTER_OTLP_HEADERS"
	// EnvExporterTimeout is the generic OTLP timeout in milliseconds.
	EnvExporterTimeout = "OTEL_EXPORTER_OTLP_TIMEOUT"
)

// SignalEnvVariable returns the signal-specific form of a generic
// OTEL_EXPORTER_OTLP_* variable, e.g. OTEL_EXPORTER_OTLP_TRACES_ENDPOINT.
func SignalEnvVariable(generic string, signal Signal) string {
	const prefix = "OTEL_EXPORTER_OTLP_"
	if !strings.HasPrefix(generic, prefix) {
		return generic
	}
	return prefix + strings.ToUpper(string(signal)) + "_" + strings.TrimPrefix(generic, prefix)
}

// OtlpSettings is the resolved OTLP wiring for one signal. A nil field means
// "pass no option and let the SDK read its own environment variable" — this is
// how C0 §4's rule that set OTEL_* variables win is honored without the engine
// re-implementing the SDK's env parsing.
type OtlpSettings struct {
	// URL is the full signal URL, or nil to defer to the SDK.
	URL *string
	// Headers are the configured export headers, or nil to defer to the SDK.
	Headers map[string]string
	// Timeout is the configured export timeout, or nil to defer to the SDK.
	Timeout *time.Duration
}

// OtlpSignalURL appends the signal path to an OTLP base endpoint. It is
// idempotent, so an endpoint that already carries `/v1/<signal>` is returned
// unchanged and a trailing slash never produces a doubled path.
func OtlpSignalURL(endpoint string, signal Signal) (string, error) {
	if !signal.Valid() {
		return "", NewFault(FaultConfigInvalid, "Invalid telemetry signal",
			"unknown signal "+strconv.Quote(string(signal)), FaultStatusInvalidInput)
	}
	if endpointErr := ValidateOtlpEndpoint(endpoint); endpointErr != nil {
		return "", endpointErr
	}
	if endpoint == "" {
		return "", NewFault(FaultEndpointInvalid, "Invalid OTLP endpoint",
			"an OTLP signal URL requires an endpoint", FaultStatusInvalidInput)
	}
	// ValidateOtlpEndpoint parsed this exact value successfully above.
	parsed, _ := url.Parse(endpoint)
	signalPath := "/v1/" + string(signal)
	base := strings.TrimSuffix(parsed.Path, "/")
	if !strings.HasSuffix(base, signalPath) {
		base += signalPath
	}
	parsed.Path = base
	return parsed.String(), nil
}

// OtlpExporterSettings resolves the OTLP wiring for one signal, deferring each
// field to the SDK whenever the matching generic or signal-specific OTEL_*
// variable is set.
func OtlpExporterSettings(
	config OtlpExporterConfig,
	signal Signal,
	system interfaces.System,
) (OtlpSettings, error) {
	if !signal.Valid() {
		return OtlpSettings{}, NewFault(FaultConfigInvalid, "Invalid telemetry signal",
			"unknown signal "+strconv.Quote(string(signal)), FaultStatusInvalidInput)
	}
	settings := OtlpSettings{}
	endpointDeferred, endpointErr := AnyEnvHasValue(system, EnvExporterEndpoint, signal)
	if endpointErr != nil {
		return OtlpSettings{}, endpointErr
	}
	if !endpointDeferred && config.Endpoint != "" {
		signalURL, urlErr := OtlpSignalURL(config.Endpoint, signal)
		if urlErr != nil {
			return OtlpSettings{}, urlErr
		}
		settings.URL = &signalURL
	}
	headersDeferred, headersErr := AnyEnvHasValue(system, EnvExporterHeaders, signal)
	if headersErr != nil {
		return OtlpSettings{}, headersErr
	}
	if !headersDeferred {
		headers := map[string]string{}
		maps.Copy(headers, config.Headers)
		settings.Headers = headers
	}
	timeoutDeferred, timeoutErr := AnyEnvHasValue(system, EnvExporterTimeout, signal)
	if timeoutErr != nil {
		return OtlpSettings{}, timeoutErr
	}
	if !timeoutDeferred {
		timeout, durationErr := ParseFixedDuration(config.Timeout)
		if durationErr != nil {
			return OtlpSettings{}, durationErr
		}
		settings.Timeout = &timeout
	}
	return settings, nil
}

// AnyEnvHasValue reports whether the generic variable or its signal-specific
// form carries a value, meaning the SDK owns that setting.
func AnyEnvHasValue(system interfaces.System, generic string, signal Signal) (bool, error) {
	signalSet, signalErr := EnvHasValue(system, SignalEnvVariable(generic, signal))
	if signalErr != nil {
		return false, signalErr
	}
	if signalSet {
		return true, nil
	}
	return EnvHasValue(system, generic)
}
