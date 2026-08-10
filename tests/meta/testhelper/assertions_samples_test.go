package testhelper_test

import (
	"errors"
	"maps"
	"testing"

	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
	"github.com/AtomiCloud/diene.go-otel/adapters/otelsdk"
	"github.com/AtomiCloud/diene.go-otel/lib/otel"
	"github.com/AtomiCloud/diene.go-otel/testhelper"
)

func TestAssertHelpersPassAndFail(t *testing.T) {
	t.Parallel()

	traceRecord := testhelper.SampleTraceRecord()
	traceEmitter := testhelper.NewInMemoryTraceEmitter()
	if err := traceEmitter.Emit(traceRecord); err != nil {
		t.Fatalf("seed trace emitter: %v", err)
	}
	logRecord := testhelper.SampleLogRecord()
	logSink := testhelper.NewInMemoryLoggerSink()
	if err := logSink.Emit(logRecord); err != nil {
		t.Fatalf("seed log sink: %v", err)
	}
	metricRecord := testhelper.SampleMetricRecord()
	metricCollector := testhelper.NewInMemoryMetricsCollector()
	if err := metricCollector.Emit(metricRecord); err != nil {
		t.Fatalf("seed metric collector: %v", err)
	}
	attributes := map[string]string{"service.name": "service"}
	active := otelsdk.ActiveSignals{Logs: true}
	fault := otel.NewFault(otel.FaultRecordInvalid, "invalid", "detail", otel.FaultStatusInvalidInput)

	passing := &recordingTestingT{}
	testhelper.AssertTraceRecords(passing, traceEmitter, []otel.TraceRecord{traceRecord})
	testhelper.AssertLogRecords(passing, logSink, []interfaces.LogRecord{logRecord})
	testhelper.AssertMetricRecords(passing, metricCollector, []interfaces.MetricRecord{metricRecord})
	testhelper.AssertResourceAttributes(passing, attributes, map[string]string{"service.name": "service"})
	testhelper.AssertActiveSignals(passing, active, active)
	testhelper.AssertProblemFault(passing, fault, otel.FaultRecordInvalid)
	if len(passing.fatals) != 0 || passing.helperCalls != 6 {
		t.Fatalf("passing assertions failed: helpers=%d fatals=%#v", passing.helperCalls, passing.fatals)
	}

	failing := &recordingTestingT{}
	testhelper.AssertTraceRecords(failing, traceEmitter, nil)
	testhelper.AssertLogRecords(failing, logSink, nil)
	testhelper.AssertMetricRecords(failing, metricCollector, nil)
	testhelper.AssertResourceAttributes(failing, attributes, map[string]string{"service.name": "changed"})
	testhelper.AssertActiveSignals(failing, active, otelsdk.ActiveSignals{})
	testhelper.AssertProblemFault(failing, fault, otel.FaultConfigInvalid)
	if len(failing.fatals) != 6 || failing.helperCalls != 6 {
		t.Fatalf("failing assertions did not report every mismatch: helpers=%d fatals=%#v",
			failing.helperCalls, failing.fatals)
	}
}

func TestProblemFaultChecks(t *testing.T) {
	t.Parallel()

	fault := otel.NewFault(otel.FaultConfigInvalid, "invalid", "detail", otel.FaultStatusInvalidInput)
	if err := testhelper.CheckProblemFault(fault, otel.FaultConfigInvalid); err != nil {
		t.Fatalf("correct fault rejected: %v", err)
	}
	if testhelper.FaultTypeURI(fault) == "" {
		t.Fatal("fault type URI missing")
	}
	if err := testhelper.CheckProblemFault(nil, otel.FaultConfigInvalid); err == nil {
		t.Fatal("nil fault accepted")
	}
	plain := errors.New("plain")
	if err := testhelper.CheckProblemFault(plain, otel.FaultConfigInvalid); err == nil {
		t.Fatal("plain error accepted")
	}
	if uri := testhelper.FaultTypeURI(plain); uri != "" {
		t.Fatalf("plain error returned URI %q", uri)
	}
	if err := testhelper.CheckProblemFault(fault, otel.FaultRecordInvalid); err == nil {
		t.Fatal("wrong fault id accepted")
	}
}

func TestSampleFixturesAreValidAndCanonical(t *testing.T) {
	t.Parallel()

	config := testhelper.SampleConfig()
	if err := config.Validate(); err != nil {
		t.Fatalf("sample config invalid: %v", err)
	}
	for _, exporter := range []otel.OtlpExporterConfig{
		config.Logs.Exporter.Otlp,
		config.Metrics.Exporter.Otlp,
		config.Traces.Exporter.Otlp,
	} {
		if !exporter.Enabled || exporter.Endpoint != "https://collector.example:4318" {
			t.Fatalf("sample exporter mismatch: %#v", exporter)
		}
	}
	identity := testhelper.SampleIdentity()
	if err := identity.Validate(); err != nil {
		t.Fatalf("sample identity invalid: %v", err)
	}
	attributes, err := otel.ResourceAttributes(identity)
	if err != nil || !maps.Equal(attributes, map[string]string{
		"deployment.environment.name": "lapras",
		"service.namespace":           "diene",
		"service.name":                "otel",
		"service.version":             "1.0.0",
		"atomi.landscape":             "lapras",
		"atomi.platform":              "diene",
		"atomi.service":               "otel",
		"atomi.module":                "engine",
		"atomi.version":               "1.0.0",
	}) {
		t.Fatalf("sample identity mapping mismatch: %#v, %v", attributes, err)
	}
	if err := testhelper.SampleTraceRecord().Validate(); err != nil {
		t.Fatalf("sample trace invalid: %v", err)
	}
	if err := otel.ValidateLogRecord(testhelper.SampleLogRecord()); err != nil {
		t.Fatalf("sample log invalid: %v", err)
	}
	if err := otel.ValidateMetricRecord(testhelper.SampleMetricRecord()); err != nil {
		t.Fatalf("sample metric invalid: %v", err)
	}
}
