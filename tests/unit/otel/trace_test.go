package otel_test

import (
	"math"
	"reflect"
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
	"github.com/AtomiCloud/diene.go-otel/lib/otel"
)

func TestTraceRecordsOwnCallerData(t *testing.T) {
	t.Parallel()

	statusMessage := "healthy"
	attributes := map[string]any{"count": 1, "tags": []string{"one", "two"}}
	eventAttributes := map[string]any{"ok": true}
	events := []otel.TraceEvent{otel.NewTraceEvent("event", eventAttributes)}
	record := otel.NewTraceRecord(
		time.Date(2026, 7, 25, 12, 30, 0, 0, time.FixedZone("offset", 3600)),
		"operation",
		attributes,
		events,
		otel.TraceStatusOK,
		&statusMessage,
	)
	attributes["count"] = 2
	eventAttributes["ok"] = false
	events[0].Name = "changed"
	statusMessage = "changed"
	if record.Timestamp.Location() != time.UTC || record.Attributes["count"] != 1 ||
		record.Events[0].Name != "event" || record.Events[0].Attributes["ok"] != bool(true) ||
		record.StatusMessage == nil || *record.StatusMessage != "healthy" {
		t.Fatalf("record does not own caller data: %#v", record)
	}
	clone := record.Clone()
	clone.Attributes["count"] = 3
	clone.Events[0].Attributes["ok"] = false
	*clone.StatusMessage = "clone"
	if record.Attributes["count"] != 1 || record.Events[0].Attributes["ok"] != bool(true) ||
		*record.StatusMessage != "healthy" {
		t.Fatal("clone aliases source record")
	}
	eventClone := record.Events[0].Clone()
	eventClone.Attributes["ok"] = false
	if record.Events[0].Attributes["ok"] != bool(true) {
		t.Fatal("event clone aliases source")
	}
	withoutOptionals := otel.NewTraceRecord(time.Time{}, "empty", nil, nil, otel.TraceStatusUnset, nil)
	if withoutOptionals.Events != nil || withoutOptionals.StatusMessage != nil || len(withoutOptionals.Attributes) != 0 {
		t.Fatalf("unexpected optional values %#v", withoutOptionals)
	}
	if err := record.Validate(); err != nil {
		t.Fatalf("valid record rejected: %v", err)
	}
}

func TestTraceVocabularyAndAttributeDomain(t *testing.T) {
	t.Parallel()

	wantStatuses := []otel.TraceStatus{otel.TraceStatusUnset, otel.TraceStatusOK, otel.TraceStatusError}
	if got := otel.TraceStatuses(); !reflect.DeepEqual(got, wantStatuses) {
		t.Fatalf("unexpected statuses %#v", got)
	}
	for _, status := range wantStatuses {
		if !otel.ValidTraceStatus(status) || status.String() == "" {
			t.Errorf("valid status rejected: %q", status)
		}
	}
	if otel.ValidTraceStatus("") || otel.ValidTraceStatus("unknown") {
		t.Fatal("unknown status accepted")
	}

	valid := []any{
		true, "text", int(1), int8(1), int16(1), int32(1), int64(1),
		uint(1), uint8(1), uint16(1), uint32(1), uint64(1),
		float32(1.5), float64(2.5),
		[]bool{true},
		[]string{"x"},
		[]int{1},
		[]int64{1},
		[]float64{1.5},
	}
	for _, value := range valid {
		if !otel.ValidAttributeValue(value) {
			t.Errorf("portable value rejected: %#v", value)
		}
	}
	invalid := []any{
		uint64(math.MaxInt64) + 1,
		uint(math.MaxInt64) + 1,
		float32(math.Inf(1)),
		math.NaN(),
		math.Inf(-1),
		[]float64{math.NaN()},
		[]uint64{1},
		struct{}{},
		nil,
	}
	for _, value := range invalid {
		if otel.ValidAttributeValue(value) {
			t.Errorf("non-portable value accepted: %#v", value)
		}
	}
	if !otel.FiniteFloat(1) || otel.FiniteFloat(math.NaN()) || otel.FiniteFloat(math.Inf(1)) {
		t.Fatal("finite-float predicate mismatch")
	}
	if err := otel.ValidateAttributes(map[string]any{"valid": []string{"one"}}); err != nil {
		t.Fatalf("valid attributes rejected: %v", err)
	}
	for _, attributes := range []map[string]any{
		{"": true},
		{"bad\x00key": true},
		{"bad": struct{}{}},
	} {
		assertProblemID(t, otel.ValidateAttributes(attributes), otel.FaultRecordInvalid)
	}
}

func TestTraceRecordValidation(t *testing.T) {
	t.Parallel()

	valid := otel.NewTraceRecord(time.Now(), "span", map[string]any{"ok": true},
		[]otel.TraceEvent{otel.NewTraceEvent("event", map[string]any{"count": 1})},
		otel.TraceStatusOK, nil)
	mutations := []func(*otel.TraceRecord){
		func(record *otel.TraceRecord) { record.Name = " " },
		func(record *otel.TraceRecord) { record.Status = "unknown" },
		func(record *otel.TraceRecord) {
			blank := " "
			record.StatusMessage = &blank
		},
		func(record *otel.TraceRecord) { record.Attributes = map[string]any{"bad": math.NaN()} },
		func(record *otel.TraceRecord) { record.Events[0].Name = " " },
		func(record *otel.TraceRecord) { record.Events[0].Attributes = map[string]any{"bad": nil} },
	}
	for _, mutate := range mutations {
		candidate := valid.Clone()
		mutate(&candidate)
		assertProblemID(t, candidate.Validate(), otel.FaultRecordInvalid)
	}
}

func TestSharedLogAndMetricRecordValidation(t *testing.T) {
	t.Parallel()

	logRecord := interfaces.NewLogRecord(time.Now(), interfaces.LogLevelInfo, "message",
		map[string]any{"ok": true}, nil, nil)
	if err := otel.ValidateLogRecord(logRecord); err != nil {
		t.Fatalf("valid log rejected: %v", err)
	}
	for _, level := range []interfaces.LogLevel{
		interfaces.LogLevelTrace,
		interfaces.LogLevelDebug,
		interfaces.LogLevelInfo,
		interfaces.LogLevelWarning,
		interfaces.LogLevelError,
		interfaces.LogLevelFatal,
	} {
		if !otel.ValidLogLevel(level) {
			t.Errorf("valid log level rejected: %q", level)
		}
	}
	logRecord.Level = "unknown"
	assertProblemID(t, otel.ValidateLogRecord(logRecord), otel.FaultRecordInvalid)
	logRecord.Level = interfaces.LogLevelInfo
	logRecord.Attributes = map[string]any{"bad": nil}
	assertProblemID(t, otel.ValidateLogRecord(logRecord), otel.FaultRecordInvalid)

	unit := "ms"
	metricRecord := interfaces.NewMetricRecord(time.Now(), "latency",
		interfaces.MetricKindHistogram, 12.5, &unit, map[string]any{"ok": true})
	if err := otel.ValidateMetricRecord(metricRecord); err != nil {
		t.Fatalf("valid metric rejected: %v", err)
	}
	for _, kind := range []interfaces.MetricKind{
		interfaces.MetricKindCounter,
		interfaces.MetricKindGauge,
		interfaces.MetricKindHistogram,
	} {
		if !otel.ValidMetricKind(kind) {
			t.Errorf("valid metric kind rejected: %q", kind)
		}
	}
	for _, mutate := range []func(*interfaces.MetricRecord){
		func(record *interfaces.MetricRecord) { record.Name = " " },
		func(record *interfaces.MetricRecord) { record.Kind = "unknown" },
		func(record *interfaces.MetricRecord) { record.Value = math.NaN() },
		func(record *interfaces.MetricRecord) { record.Attributes = map[string]any{"bad": nil} },
	} {
		candidate := metricRecord.Clone()
		mutate(&candidate)
		assertProblemID(t, otel.ValidateMetricRecord(candidate), otel.FaultRecordInvalid)
	}
}
