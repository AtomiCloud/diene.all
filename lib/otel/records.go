package otel

import (
	"strings"

	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
)

// ValidLogLevel reports whether level belongs to the published logging
// vocabulary shared by every Diene Go component.
func ValidLogLevel(level interfaces.LogLevel) bool {
	switch level {
	case interfaces.LogLevelTrace, interfaces.LogLevelDebug, interfaces.LogLevelInfo,
		interfaces.LogLevelWarning, interfaces.LogLevelError, interfaces.LogLevelFatal:
		return true
	default:
		return false
	}
}

// ValidateLogRecord reports whether record can be emitted by both the real sink
// and the shipped in-memory double.
func ValidateLogRecord(record interfaces.LogRecord) error {
	if !ValidLogLevel(record.Level) {
		return NewFault(FaultRecordInvalid, "Invalid log record",
			"unknown log level "+string(record.Level), FaultStatusInvalidInput)
	}
	return ValidateAttributes(record.Attributes)
}

// ValidMetricKind reports whether kind belongs to the published metrics
// vocabulary shared by every Diene Go component.
func ValidMetricKind(kind interfaces.MetricKind) bool {
	switch kind {
	case interfaces.MetricKindCounter, interfaces.MetricKindGauge, interfaces.MetricKindHistogram:
		return true
	default:
		return false
	}
}

// ValidateMetricRecord reports whether record can be emitted by both the real
// collector and the shipped in-memory double.
func ValidateMetricRecord(record interfaces.MetricRecord) error {
	if strings.TrimSpace(record.Name) == "" {
		return NewFault(FaultRecordInvalid, "Invalid metric record",
			"metric name must not be blank", FaultStatusInvalidInput)
	}
	if !ValidMetricKind(record.Kind) {
		return NewFault(FaultRecordInvalid, "Invalid metric record",
			"unknown metric kind "+string(record.Kind), FaultStatusInvalidInput)
	}
	if !FiniteFloat(record.Value) {
		return NewFault(FaultRecordInvalid, "Invalid metric record",
			"metric value must be finite", FaultStatusInvalidInput)
	}
	return ValidateAttributes(record.Attributes)
}
