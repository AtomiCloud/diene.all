package otel_test

import (
	"errors"
	"reflect"
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-interfaces/testhelper"
	"github.com/AtomiCloud/diene.go-otel/lib/otel"
)

func TestSignalVocabulary(t *testing.T) {
	t.Parallel()

	want := []otel.Signal{otel.SignalLogs, otel.SignalMetrics, otel.SignalTraces}
	if got := otel.Signals(); !reflect.DeepEqual(got, want) {
		t.Fatalf("unexpected signals: %#v", got)
	}
	for _, signal := range want {
		if !signal.Valid() {
			t.Errorf("expected %q to be valid", signal)
		}
		if signal.String() == "" || signal.ExporterEnvVariable() == "" {
			t.Errorf("expected names for %q", signal)
		}
	}
	unknown := otel.Signal("unknown")
	if unknown.Valid() || unknown.ExporterEnvVariable() != "" {
		t.Fatal("unknown signal unexpectedly accepted")
	}
	if (otel.Selection{}).Any() {
		t.Fatal("empty selection must be inactive")
	}
	if !(otel.Selection{Console: true}).Any() || !(otel.Selection{Otlp: true}).Any() {
		t.Fatal("selected exporter must be active")
	}
}

func TestEnvironmentReadsAndSDKDisabled(t *testing.T) {
	t.Parallel()

	if _, err := otel.EnvValue(nil, "OTEL_TEST"); err == nil {
		t.Fatal("nil system must fail")
	}
	system := systemWith(map[string]string{
		"PRESENT":           "value",
		"BLANK":             "  ",
		otel.EnvSDKDisabled: " TrUe ",
	})
	value, err := otel.EnvValue(system, "PRESENT")
	if err != nil || value == nil || *value != "value" {
		t.Fatalf("unexpected environment read: %v, %v", value, err)
	}
	missing, err := otel.EnvValue(system, "MISSING")
	if err != nil || missing != nil {
		t.Fatalf("unexpected missing environment result: %v, %v", missing, err)
	}
	hasValue, err := otel.EnvHasValue(system, "PRESENT")
	if err != nil || !hasValue {
		t.Fatalf("present value not detected: %v", err)
	}
	hasValue, err = otel.EnvHasValue(system, "BLANK")
	if err != nil || hasValue {
		t.Fatalf("blank value must be treated as unset: %v", err)
	}
	disabled, err := otel.SDKDisabled(system)
	if err != nil || !disabled {
		t.Fatalf("SDK disabled override not honored: %v", err)
	}
	disabled, err = otel.SDKDisabled(systemWith(nil))
	if err != nil || disabled {
		t.Fatalf("absent SDK override must not disable: %v", err)
	}
	disabled, err = otel.SDKDisabled(systemWith(map[string]string{otel.EnvSDKDisabled: "false"}))
	if err != nil || disabled {
		t.Fatalf("false SDK override must not disable: %v", err)
	}
}

func TestEnvironmentFailuresAreProblemTyped(t *testing.T) {
	t.Parallel()

	system := testhelper.NewInMemorySystem(testhelper.InMemorySystemOptions{})
	sentinel := errors.New("environment unavailable")
	system.EnqueueEnvironmentResult(nil, sentinel)
	_, err := otel.EnvValue(system, "BROKEN")
	if !errors.Is(err, sentinel) {
		t.Fatalf("expected wrapped sentinel, got %v", err)
	}
	if _, hasErr := otel.EnvHasValue(nil, "BROKEN"); hasErr == nil {
		t.Fatal("expected EnvHasValue failure")
	}
	if _, disabledErr := otel.SDKDisabled(nil); disabledErr == nil {
		t.Fatal("expected SDKDisabled failure")
	}
}

func TestExporterSelection(t *testing.T) {
	t.Parallel()

	config := otel.ExporterConfig{
		Console: otel.ConsoleExporterConfig{Enabled: true},
		Otlp:    otel.OtlpExporterConfig{Enabled: true},
	}
	selection, err := otel.ExporterSelection(config, otel.SignalLogs, systemWith(nil))
	if err != nil || selection != (otel.Selection{Console: true, Otlp: true}) {
		t.Fatalf("block selection mismatch: %+v, %v", selection, err)
	}
	selection, err = otel.ExporterSelection(config, otel.SignalLogs,
		systemWith(map[string]string{otel.EnvLogsExporter: "console, OTLP"}))
	if err != nil || selection != (otel.Selection{Console: true, Otlp: true}) {
		t.Fatalf("env selection mismatch: %+v, %v", selection, err)
	}
	selection, err = otel.ExporterSelection(config, otel.SignalMetrics,
		systemWith(map[string]string{otel.EnvMetricsExporter: "none,console"}))
	if err != nil || selection.Any() {
		t.Fatalf("none must disable everything: %+v, %v", selection, err)
	}
	selection, err = otel.ExporterSelection(config, otel.SignalTraces,
		systemWith(map[string]string{otel.EnvTracesExporter: "unknown"}))
	if err != nil || selection.Any() {
		t.Fatalf("unknown override must select nothing: %+v, %v", selection, err)
	}
	selection, err = otel.ExporterSelection(config, otel.SignalTraces,
		systemWith(map[string]string{otel.EnvTracesExporter: "  "}))
	if err != nil || selection != (otel.Selection{Console: true, Otlp: true}) {
		t.Fatalf("blank override must keep block: %+v, %v", selection, err)
	}
	_, err = otel.ExporterSelection(config, "unknown", systemWith(nil))
	assertProblemID(t, err, otel.FaultConfigInvalid)
	_, err = otel.ExporterSelection(config, otel.SignalLogs, nil)
	assertProblemID(t, err, otel.FaultEnvironmentUnavailable)
}

func TestOtlpSignalURL(t *testing.T) {
	t.Parallel()

	tests := map[string]string{
		"https://collector.example:4318":             "https://collector.example:4318/v1/traces",
		"https://collector.example:4318/":            "https://collector.example:4318/v1/traces",
		"https://collector.example:4318/base":        "https://collector.example:4318/base/v1/traces",
		"https://collector.example:4318/v1/traces":   "https://collector.example:4318/v1/traces",
		"https://collector.example:4318/base/?x=yes": "https://collector.example:4318/base/v1/traces?x=yes",
	}
	for endpoint, want := range tests {
		got, err := otel.OtlpSignalURL(endpoint, otel.SignalTraces)
		if err != nil || got != want {
			t.Errorf("OtlpSignalURL(%q): want %q, got %q (%v)", endpoint, want, got, err)
		}
	}
	_, err := otel.OtlpSignalURL("", otel.SignalLogs)
	assertProblemID(t, err, otel.FaultEndpointInvalid)
	_, err = otel.OtlpSignalURL("https://collector.example:4317", otel.SignalLogs)
	assertProblemID(t, err, otel.FaultEndpointInvalid)
	_, err = otel.OtlpSignalURL("https://collector.example:4318", "unknown")
	assertProblemID(t, err, otel.FaultConfigInvalid)
}

func TestOtlpExporterSettingsAndDeferral(t *testing.T) {
	t.Parallel()

	config := otel.OtlpExporterConfig{
		Enabled:  true,
		Endpoint: "https://collector.example:4318",
		Protocol: otel.ProtocolHTTPProtobuf,
		Headers:  map[string]string{"authorization": "secret"},
		Timeout:  "PT10S",
	}
	settings, err := otel.OtlpExporterSettings(config, otel.SignalLogs, systemWith(nil))
	if err != nil {
		t.Fatalf("settings failed: %v", err)
	}
	if settings.URL == nil || *settings.URL != "https://collector.example:4318/v1/logs" {
		t.Fatalf("unexpected URL %#v", settings.URL)
	}
	if settings.Headers["authorization"] != "secret" {
		t.Fatalf("unexpected headers %#v", settings.Headers)
	}
	if settings.Timeout == nil || *settings.Timeout != 10*time.Second {
		t.Fatalf("unexpected timeout %#v", settings.Timeout)
	}

	for _, environment := range []map[string]string{
		{otel.EnvExporterEndpoint: "https://generic.example:4318"},
		{otel.SignalEnvVariable(otel.EnvExporterEndpoint, otel.SignalLogs): "https://logs.example:4318"},
	} {
		deferred, deferErr := otel.OtlpExporterSettings(config, otel.SignalLogs, systemWith(environment))
		if deferErr != nil || deferred.URL != nil {
			t.Fatalf("endpoint must defer: %#v, %v", deferred, deferErr)
		}
	}
	for _, environment := range []map[string]string{
		{otel.EnvExporterHeaders: "authorization=env"},
		{otel.SignalEnvVariable(otel.EnvExporterHeaders, otel.SignalLogs): "authorization=env"},
	} {
		deferred, deferErr := otel.OtlpExporterSettings(config, otel.SignalLogs, systemWith(environment))
		if deferErr != nil || deferred.Headers != nil {
			t.Fatalf("headers must defer: %#v, %v", deferred, deferErr)
		}
	}
	for _, environment := range []map[string]string{
		{otel.EnvExporterTimeout: "1000"},
		{otel.SignalEnvVariable(otel.EnvExporterTimeout, otel.SignalLogs): "1000"},
	} {
		deferred, deferErr := otel.OtlpExporterSettings(config, otel.SignalLogs, systemWith(environment))
		if deferErr != nil || deferred.Timeout != nil {
			t.Fatalf("timeout must defer: %#v, %v", deferred, deferErr)
		}
	}

	empty := config
	empty.Endpoint = ""
	settings, err = otel.OtlpExporterSettings(empty, otel.SignalMetrics, systemWith(nil))
	if err != nil || settings.URL != nil {
		t.Fatalf("empty endpoint should remain unset: %#v, %v", settings, err)
	}
	_, err = otel.OtlpExporterSettings(config, "unknown", systemWith(nil))
	assertProblemID(t, err, otel.FaultConfigInvalid)

	badDuration := config
	badDuration.Timeout = "PT"
	_, err = otel.OtlpExporterSettings(badDuration, otel.SignalLogs, systemWith(nil))
	assertProblemID(t, err, otel.FaultDurationInvalid)

	badEndpoint := config
	badEndpoint.Endpoint = "https://collector.example:4317"
	_, err = otel.OtlpExporterSettings(badEndpoint, otel.SignalLogs, systemWith(nil))
	assertProblemID(t, err, otel.FaultEndpointInvalid)

	for failureIndex := range 3 {
		broken := testhelper.NewInMemorySystem(testhelper.InMemorySystemOptions{})
		for range failureIndex * 2 {
			broken.EnqueueEnvironmentResult(nil, nil)
		}
		broken.EnqueueEnvironmentResult(nil, errors.New("environment failed"))
		_, err = otel.OtlpExporterSettings(config, otel.SignalLogs, broken)
		if err == nil {
			t.Fatalf("expected environment failure at setting %d", failureIndex)
		}
	}
}

func TestSignalEnvironmentVariable(t *testing.T) {
	t.Parallel()

	if got := otel.SignalEnvVariable(otel.EnvExporterEndpoint, otel.SignalMetrics); got != "OTEL_EXPORTER_OTLP_METRICS_ENDPOINT" {
		t.Fatalf("unexpected signal variable %q", got)
	}
	if got := otel.SignalEnvVariable("CUSTOM", otel.SignalLogs); got != "CUSTOM" {
		t.Fatalf("non-OTLP variable must be unchanged, got %q", got)
	}
	present, err := otel.AnyEnvHasValue(systemWith(map[string]string{
		"OTEL_EXPORTER_OTLP_TRACES_ENDPOINT": "https://traces.example:4318",
	}), otel.EnvExporterEndpoint, otel.SignalTraces)
	if err != nil || !present {
		t.Fatalf("signal override not found: %v", err)
	}
	present, err = otel.AnyEnvHasValue(systemWith(map[string]string{
		otel.EnvExporterEndpoint: "https://generic.example:4318",
	}), otel.EnvExporterEndpoint, otel.SignalTraces)
	if err != nil || !present {
		t.Fatalf("generic override not found: %v", err)
	}
	present, err = otel.AnyEnvHasValue(systemWith(nil), otel.EnvExporterEndpoint, otel.SignalTraces)
	if err != nil || present {
		t.Fatalf("absent override unexpectedly found: %v", err)
	}
}
