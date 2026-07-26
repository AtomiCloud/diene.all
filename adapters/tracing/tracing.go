// Package tracing provides the shared telemetry span helper used by adapters.
package tracing

import (
	"errors"
	"time"

	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
	"github.com/AtomiCloud/diene.go-otel/lib/otel"
)

// Tracer creates completed portable trace records through the Diene OTEL seam.
type Tracer struct {
	system  interfaces.System
	emitter otel.TraceEmitter
}

// Span is one started adapter operation awaiting its outcome.
type Span struct {
	emitter    otel.TraceEmitter
	timestamp  time.Time
	name       string
	attributes map[string]any
}

// New constructs a tracer from the process/clock seam and trace emitter.
func New(system interfaces.System, emitter otel.TraceEmitter) (*Tracer, error) {
	if system == nil {
		return nil, errors.New("tracing: system is required")
	}
	if emitter == nil {
		return nil, errors.New("tracing: emitter is required")
	}
	return &Tracer{system: system, emitter: emitter}, nil
}

// Start begins a completed-record span using the injected UTC clock.
func (t *Tracer) Start(name string, attributes map[string]any) (*Span, error) {
	startedAt, err := t.system.NowUTC()
	if err != nil {
		return nil, err
	}
	return &Span{
		emitter:    t.emitter,
		timestamp:  startedAt,
		name:       name,
		attributes: interfaces.CloneAttributes(attributes),
	}, nil
}

// End emits the span outcome. If both the operation and telemetry fail, the
// joined result preserves the original failure for errors.Is/errors.As.
func (s *Span) End(operationErr error) error {
	status := otel.TraceStatusOK
	var statusMessage *string
	if operationErr != nil {
		status = otel.TraceStatusError
		message := operationErr.Error()
		statusMessage = &message
	}
	emitErr := s.emitter.Emit(otel.NewTraceRecord(
		s.timestamp,
		s.name,
		s.attributes,
		nil,
		status,
		statusMessage,
	))
	switch {
	case operationErr != nil && emitErr != nil:
		return errors.Join(operationErr, emitErr)
	case operationErr != nil:
		return operationErr
	default:
		return emitErr
	}
}
