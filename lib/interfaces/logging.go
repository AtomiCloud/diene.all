package interfaces

import (
	"maps"
	"time"
)

// LogLevel is the severity of a structured log record.
type LogLevel string

const (
	// LogLevelTrace is the most detailed diagnostic level.
	LogLevelTrace LogLevel = "trace"
	// LogLevelDebug is diagnostic information for development.
	LogLevelDebug LogLevel = "debug"
	// LogLevelInfo records normal application progress.
	LogLevelInfo LogLevel = "info"
	// LogLevelWarning records a recoverable abnormal condition.
	LogLevelWarning LogLevel = "warning"
	// LogLevelError records a failed operation.
	LogLevelError LogLevel = "error"
	// LogLevelFatal records an unrecoverable condition.
	LogLevelFatal LogLevel = "fatal"
)

// String returns the portable wire name of l.
func (l LogLevel) String() string { return string(l) }

// LogRecord is one structured log emission.
type LogRecord struct {
	// Timestamp is when the event occurred.
	Timestamp time.Time
	// Level is the event severity.
	Level LogLevel
	// Message is the human-readable event description.
	Message string
	// Attributes is a structured, independently owned copy of caller input.
	Attributes map[string]any
	// Error is an optional error description.
	Error *string
	// StackTrace is an optional stack trace.
	StackTrace *string
}

// NewLogRecord creates a record with copied attributes and optional strings.
func NewLogRecord(timestamp time.Time, level LogLevel, message string, attributes map[string]any, errorMessage, stackTrace *string) LogRecord {
	record := LogRecord{Timestamp: timestamp.UTC(), Level: level, Message: message, Attributes: CloneAttributes(attributes)}
	if errorMessage != nil {
		copied := *errorMessage
		record.Error = &copied
	}
	if stackTrace != nil {
		copied := *stackTrace
		record.StackTrace = &copied
	}
	return record
}

// Clone returns a record with independently owned attributes and optional strings.
func (r LogRecord) Clone() LogRecord {
	return NewLogRecord(r.Timestamp, r.Level, r.Message, r.Attributes, r.Error, r.StackTrace)
}

// CloneAttributes returns an independent shallow copy of attributes.
func CloneAttributes(attributes map[string]any) map[string]any {
	if attributes == nil {
		return map[string]any{}
	}
	return maps.Clone(attributes)
}

// LoggerSink receives structured application logs. Every non-nil error returned
// by an implementation must be problem-typed.
type LoggerSink interface {
	// Emit delivers record.
	Emit(record LogRecord) error
}
