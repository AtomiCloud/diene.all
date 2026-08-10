package testhelper_test

import (
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
	"github.com/AtomiCloud/diene.go-otel/adapters/otelsdk"
	"github.com/AtomiCloud/diene.go-otel/lib/otel"
	"github.com/AtomiCloud/diene.go-otel/testhelper"
)

func TestCheckTraceRecordsAndRecord(t *testing.T) {
	t.Parallel()

	want := testhelper.SampleTraceRecord()
	if err := testhelper.CheckTraceRecords([]otel.TraceRecord{want.Clone()}, []otel.TraceRecord{want}); err != nil {
		t.Fatalf("equal traces rejected: %v", err)
	}
	if err := testhelper.CheckTraceRecords(nil, []otel.TraceRecord{want}); err == nil {
		t.Fatal("trace length mismatch accepted")
	}

	mutations := []func(*otel.TraceRecord){
		func(record *otel.TraceRecord) { record.Name = "changed" },
		func(record *otel.TraceRecord) { record.Timestamp = record.Timestamp.Add(time.Second) },
		func(record *otel.TraceRecord) { record.Status = otel.TraceStatusError },
		func(record *otel.TraceRecord) { message := "changed"; record.StatusMessage = &message },
		func(record *otel.TraceRecord) { record.Attributes["sample"] = false },
		func(record *otel.TraceRecord) { record.Events = nil },
		func(record *otel.TraceRecord) { record.Events[0].Name = "changed" },
		func(record *otel.TraceRecord) { record.Events[0].Attributes["index"] = 2 },
	}
	for _, mutate := range mutations {
		actual := want.Clone()
		mutate(&actual)
		if err := testhelper.CheckTraceRecord(actual, want); err == nil {
			t.Fatalf("trace mismatch accepted: %#v", actual)
		}
		if err := testhelper.CheckTraceRecords([]otel.TraceRecord{actual}, []otel.TraceRecord{want}); err == nil {
			t.Fatal("nested trace mismatch accepted")
		}
	}
}

func TestCheckAttributesAndOptionalStrings(t *testing.T) {
	t.Parallel()

	if err := testhelper.CheckAttributes(nil, map[string]any{}); err != nil {
		t.Fatalf("nil and empty attributes must agree: %v", err)
	}
	if err := testhelper.CheckAttributes(map[string]any{"one": 1}, map[string]any{}); err == nil {
		t.Fatal("attribute length mismatch accepted")
	}
	if err := testhelper.CheckAttributes(map[string]any{"actual": 1}, map[string]any{"want": 1}); err == nil {
		t.Fatal("missing attribute accepted")
	}
	if err := testhelper.CheckAttributes(map[string]any{"key": 1}, map[string]any{"key": 2}); err == nil {
		t.Fatal("attribute value mismatch accepted")
	}
	if !testhelper.EqualAttributeValue([]string{"one"}, []string{"one"}) ||
		testhelper.EqualAttributeValue([]string{"one"}, []string{"two"}) {
		t.Fatal("attribute equality mismatch")
	}

	one := "one"
	two := "two"
	tests := []struct {
		actual *string
		want   *string
		ok     bool
	}{
		{actual: nil, want: nil, ok: true},
		{actual: nil, want: &one},
		{actual: &one, want: nil},
		{actual: &one, want: &two},
		{actual: &one, want: &one, ok: true},
	}
	for _, test := range tests {
		err := testhelper.CheckOptionalString("value", test.actual, test.want)
		if (err == nil) != test.ok {
			t.Errorf("optional string verdict mismatch: %v", err)
		}
	}
}

func TestCheckLogRecords(t *testing.T) {
	t.Parallel()

	errorMessage := "error"
	stackTrace := "stack"
	want := interfaces.NewLogRecord(time.Now(), interfaces.LogLevelError, "message",
		map[string]any{"key": "value"}, &errorMessage, &stackTrace)
	if err := testhelper.CheckLogRecords([]interfaces.LogRecord{want.Clone()}, []interfaces.LogRecord{want}); err != nil {
		t.Fatalf("equal logs rejected: %v", err)
	}
	if err := testhelper.CheckLogRecords(nil, []interfaces.LogRecord{want}); err == nil {
		t.Fatal("log length mismatch accepted")
	}
	mutations := []func(*interfaces.LogRecord){
		func(record *interfaces.LogRecord) { record.Level = interfaces.LogLevelInfo },
		func(record *interfaces.LogRecord) { record.Message = "changed" },
		func(record *interfaces.LogRecord) { record.Timestamp = record.Timestamp.Add(time.Second) },
		func(record *interfaces.LogRecord) { record.Attributes["key"] = "changed" },
		func(record *interfaces.LogRecord) { record.Error = nil },
		func(record *interfaces.LogRecord) { record.StackTrace = nil },
	}
	for _, mutate := range mutations {
		actual := want.Clone()
		mutate(&actual)
		if err := testhelper.CheckLogRecords([]interfaces.LogRecord{actual}, []interfaces.LogRecord{want}); err == nil {
			t.Fatalf("log mismatch accepted: %#v", actual)
		}
	}
}

func TestCheckMetricRecords(t *testing.T) {
	t.Parallel()

	unit := "ms"
	want := interfaces.NewMetricRecord(time.Now(), "latency", interfaces.MetricKindHistogram, 1.5,
		&unit, map[string]any{"key": "value"})
	if err := testhelper.CheckMetricRecords([]interfaces.MetricRecord{want.Clone()}, []interfaces.MetricRecord{want}); err != nil {
		t.Fatalf("equal metrics rejected: %v", err)
	}
	if err := testhelper.CheckMetricRecords(nil, []interfaces.MetricRecord{want}); err == nil {
		t.Fatal("metric length mismatch accepted")
	}
	mutations := []func(*interfaces.MetricRecord){
		func(record *interfaces.MetricRecord) { record.Timestamp = record.Timestamp.Add(time.Second) },
		func(record *interfaces.MetricRecord) { record.Name = "changed" },
		func(record *interfaces.MetricRecord) { record.Kind = interfaces.MetricKindGauge },
		func(record *interfaces.MetricRecord) { record.Value = 2 },
		func(record *interfaces.MetricRecord) { record.Unit = nil },
		func(record *interfaces.MetricRecord) { record.Attributes["key"] = "changed" },
	}
	for _, mutate := range mutations {
		actual := want.Clone()
		mutate(&actual)
		if err := testhelper.CheckMetricRecords([]interfaces.MetricRecord{actual}, []interfaces.MetricRecord{want}); err == nil {
			t.Fatalf("metric mismatch accepted: %#v", actual)
		}
	}
}

func TestCheckResourceAttributesAndActiveSignals(t *testing.T) {
	t.Parallel()

	attributes := map[string]string{"service.name": "service"}
	if err := testhelper.CheckResourceAttributes(attributes, map[string]string{"service.name": "service"}); err != nil {
		t.Fatalf("equal resource attributes rejected: %v", err)
	}
	if err := testhelper.CheckResourceAttributes(attributes, map[string]string{"service.name": "changed"}); err == nil {
		t.Fatal("resource attribute mismatch accepted")
	}
	active := otelsdk.ActiveSignals{Logs: true, Metrics: true, Traces: true}
	if err := testhelper.CheckActiveSignals(active, active); err != nil {
		t.Fatalf("equal active signals rejected: %v", err)
	}
	if err := testhelper.CheckActiveSignals(active, otelsdk.ActiveSignals{}); err == nil {
		t.Fatal("active-signal mismatch accepted")
	}
}
