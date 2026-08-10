package otel

import (
	"math"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
)

// TraceStatus is the outcome recorded on an emitted span.
type TraceStatus string

const (
	// TraceStatusUnset leaves the span outcome undeclared.
	TraceStatusUnset TraceStatus = "unset"
	// TraceStatusOK records a successful operation.
	TraceStatusOK TraceStatus = "ok"
	// TraceStatusError records a failed operation.
	TraceStatusError TraceStatus = "error"
)

// String returns the portable wire name of s.
func (s TraceStatus) String() string { return string(s) }

// TraceStatuses returns every status vocabulary member in canonical order.
func TraceStatuses() []TraceStatus {
	return []TraceStatus{TraceStatusUnset, TraceStatusOK, TraceStatusError}
}

// TraceEvent is one timestamped annotation on a span.
type TraceEvent struct {
	// Name is the event name.
	Name string
	// Attributes is a structured, independently owned copy of caller input.
	Attributes map[string]any
}

// NewTraceEvent creates an event with copied attributes.
func NewTraceEvent(name string, attributes map[string]any) TraceEvent {
	return TraceEvent{Name: name, Attributes: interfaces.CloneAttributes(attributes)}
}

// Clone returns an event with independently owned attributes.
func (e TraceEvent) Clone() TraceEvent { return NewTraceEvent(e.Name, e.Attributes) }

// TraceRecord is one completed span emitted by an application.
//
// The record is deliberately a completed span rather than a live span handle:
// the seam stays a plain value type, so a consumer's tests assert emitted data
// instead of driving an SDK object graph.
type TraceRecord struct {
	// Timestamp is when the span started.
	Timestamp time.Time
	// Name is the span name.
	Name string
	// Attributes is a structured, independently owned copy of caller input.
	Attributes map[string]any
	// Events are the span's annotations, independently owned.
	Events []TraceEvent
	// Status is the span outcome.
	Status TraceStatus
	// StatusMessage is an optional description of the outcome.
	StatusMessage *string
}

// NewTraceRecord creates a record with copied attributes, events, and optional
// message, so later mutation of the caller's maps or slices cannot reach it.
func NewTraceRecord(
	timestamp time.Time,
	name string,
	attributes map[string]any,
	events []TraceEvent,
	status TraceStatus,
	statusMessage *string,
) TraceRecord {
	record := TraceRecord{
		Timestamp:  timestamp.UTC(),
		Name:       name,
		Attributes: interfaces.CloneAttributes(attributes),
		Status:     status,
	}
	if events != nil {
		record.Events = make([]TraceEvent, 0, len(events))
		for _, event := range events {
			record.Events = append(record.Events, event.Clone())
		}
	}
	if statusMessage != nil {
		copied := *statusMessage
		record.StatusMessage = &copied
	}
	return record
}

// Clone returns a record with independently owned attributes, events, and message.
func (r TraceRecord) Clone() TraceRecord {
	return NewTraceRecord(r.Timestamp, r.Name, r.Attributes, r.Events, r.Status, r.StatusMessage)
}

// Validate reports whether the record can be emitted: a non-blank span name, a
// known status, non-blank event names, and attribute values within the portable
// telemetry domain.
func (r TraceRecord) Validate() error {
	if strings.TrimSpace(r.Name) == "" {
		return NewFault(FaultRecordInvalid, "Invalid trace record",
			"span name must not be blank", FaultStatusInvalidInput)
	}
	if !ValidTraceStatus(r.Status) {
		return NewFault(FaultRecordInvalid, "Invalid trace record",
			"unknown trace status "+strconv.Quote(string(r.Status)), FaultStatusInvalidInput)
	}
	if r.StatusMessage != nil && strings.TrimSpace(*r.StatusMessage) == "" {
		return NewFault(FaultRecordInvalid, "Invalid trace record",
			"status message must not be blank when present", FaultStatusInvalidInput)
	}
	if attributesErr := ValidateAttributes(r.Attributes); attributesErr != nil {
		return attributesErr
	}
	for _, event := range r.Events {
		if strings.TrimSpace(event.Name) == "" {
			return NewFault(FaultRecordInvalid, "Invalid trace record",
				"event name must not be blank", FaultStatusInvalidInput)
		}
		if attributesErr := ValidateAttributes(event.Attributes); attributesErr != nil {
			return attributesErr
		}
	}
	return nil
}

// ValidTraceStatus reports whether status is a member of the frozen vocabulary.
// The zero value of [TraceStatus] is NOT a member: a record must declare its
// outcome explicitly, so a forgotten status is a fault rather than a silent unset.
func ValidTraceStatus(status TraceStatus) bool {
	return slices.Contains(TraceStatuses(), status)
}

// ValidateAttributes reports whether every attribute name and value is portable
// telemetry data. Names must be non-blank and free of NUL; values must satisfy
// [ValidAttributeValue].
func ValidateAttributes(attributes map[string]any) error {
	for name, value := range attributes {
		if strings.TrimSpace(name) == "" || strings.ContainsRune(name, 0) {
			return NewFault(FaultRecordInvalid, "Invalid telemetry attribute",
				"attribute names must be non-blank and NUL-free", FaultStatusInvalidInput)
		}
		if !ValidAttributeValue(value) {
			return NewFault(FaultRecordInvalid, "Invalid telemetry attribute",
				"attribute "+strconv.Quote(name)+" is not portable telemetry data", FaultStatusInvalidInput)
		}
	}
	return nil
}

// ValidAttributeValue reports whether value is portable telemetry data.
//
// The accepted domain is deliberately the OpenTelemetry attribute domain, which
// has exactly four value kinds — bool, int64, float64, string — plus a
// homogeneous array of each. Scalars of any signed or unsigned integer width and
// float32 are accepted and widened by the adapter; ARRAYS are accepted only in
// the four portable forms []bool, []string, []int64, and []float64 (plus []int,
// widened to []int64), because no other slice type survives the conversion. Every
// floating-point value must be finite: NaN and ±Inf have no wire representation.
//
// Unsigned integers above [math.MaxInt64] are REJECTED rather than wrapped: the
// attribute domain is signed 64-bit, so wrapping would emit a negative number for
// a positive measurement.
func ValidAttributeValue(value any) bool {
	switch typed := value.(type) {
	case bool, string, int, int8, int16, int32, int64, uint8, uint16, uint32:
		return true
	case uint:
		return uint64(typed) <= math.MaxInt64
	case uint64:
		return typed <= math.MaxInt64
	case float32:
		return FiniteFloat(float64(typed))
	case float64:
		return FiniteFloat(typed)
	case []bool, []string, []int, []int64:
		return true
	case []float64:
		for _, member := range typed {
			if !FiniteFloat(member) {
				return false
			}
		}
		return true
	default:
		return false
	}
}

// FiniteFloat reports whether value has a wire representation: NaN and ±Inf do not.
func FiniteFloat(value float64) bool {
	return !math.IsNaN(value) && !math.IsInf(value, 0)
}

// TraceEmitter receives completed spans. Every non-nil error returned by an
// implementation must be problem-typed.
//
// This seam is owned by the otel engine rather than the shared interfaces
// library because trace test seams are language-local: no cross-language shape
// parity is required, so each language family ships its own tracer interface,
// mock, and TestHelper.
type TraceEmitter interface {
	// Emit delivers record.
	Emit(record TraceRecord) error
}
