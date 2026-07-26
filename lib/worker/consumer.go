// Package worker coordinates stream consumption, the domain handler, worker
// heartbeat, and telemetry without importing concrete adapters.
package worker

import (
	"context"
	"errors"
	"fmt"
	"maps"

	"github.com/AtomiCloud/diene.go-consumer/lib/health"
	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
)

// Envelope is one Redis-stream message delivered to the worker.
type Envelope struct {
	ID      string
	Payload string
}

// HandleResult is the domain result recorded in a successful worker log.
type HandleResult struct {
	MessageID string
	Inserted  bool
	ObjectKey string
}

// Transport is the stream port the consumer owns.
type Transport interface {
	EnsureGroup(ctx context.Context) error
	ReclaimPending(ctx context.Context) ([]Envelope, error)
	Consume(ctx context.Context) ([]Envelope, error)
	Acknowledge(ctx context.Context, id string) (int64, error)
}

// Decoder validates and decodes one stream payload.
type Decoder[Message any] interface {
	Decode(ctx context.Context, payload string) (Message, error)
}

// Handler performs the domain side effects for one decoded message.
type Handler[Message any] interface {
	Handle(ctx context.Context, message Message) (HandleResult, error)
}

// Heartbeat writes worker lifecycle state.
type Heartbeat interface {
	Write(ctx context.Context, state health.State) error
}

// Options configures a Consumer.
type Options[Message any] struct {
	Transport          Transport
	Decoder            Decoder[Message]
	Handler            Handler[Message]
	Heartbeat          Heartbeat
	System             interfaces.System
	Logger             interfaces.LoggerSink
	Metrics            interfaces.MetricsCollector
	MaxMessageBytes    int
	IdentityAttributes map[string]string
}

// Consumer coordinates one stream consumer loop.
type Consumer[Message any] struct {
	transport          Transport
	decoder            Decoder[Message]
	handler            Handler[Message]
	heartbeat          Heartbeat
	system             interfaces.System
	logger             interfaces.LoggerSink
	metrics            interfaces.MetricsCollector
	maxMessageBytes    int
	identityAttributes map[string]string
}

// NewConsumer creates a fully injected worker consumer.
func NewConsumer[Message any](options Options[Message]) (*Consumer[Message], error) {
	if options.Transport == nil {
		return nil, errors.New("worker: transport is required")
	}
	if options.Decoder == nil {
		return nil, errors.New("worker: decoder is required")
	}
	if options.Handler == nil {
		return nil, errors.New("worker: handler is required")
	}
	if options.Heartbeat == nil {
		return nil, errors.New("worker: heartbeat is required")
	}
	if options.System == nil {
		return nil, errors.New("worker: system is required")
	}
	if options.Logger == nil {
		return nil, errors.New("worker: logger is required")
	}
	if options.Metrics == nil {
		return nil, errors.New("worker: metrics collector is required")
	}
	if options.MaxMessageBytes <= 0 {
		return nil, errors.New("worker: max message bytes must be positive")
	}
	return &Consumer[Message]{
		transport:          options.Transport,
		decoder:            options.Decoder,
		handler:            options.Handler,
		heartbeat:          options.Heartbeat,
		system:             options.System,
		logger:             options.Logger,
		metrics:            options.Metrics,
		maxMessageBytes:    options.MaxMessageBytes,
		identityAttributes: maps.Clone(options.IdentityAttributes),
	}, nil
}

// EmitLog writes one structured worker log using the injected clock and sink.
func (c *Consumer[Message]) EmitLog(
	level interfaces.LogLevel,
	message string,
	attributes map[string]any,
	cause error,
) error {
	now, err := c.system.NowUTC()
	if err != nil {
		return fmt.Errorf("worker: read log clock: %w", err)
	}
	var errorMessage *string
	if cause != nil {
		text := cause.Error()
		errorMessage = &text
	}
	if err := c.logger.Emit(interfaces.NewLogRecord(now, level, message, attributes, errorMessage, nil)); err != nil {
		return fmt.Errorf("worker: emit log: %w", err)
	}
	return nil
}

// RefreshHeartbeat records state in the heartbeat and health metric. Telemetry
// sink failures are best-effort and do not make a healthy worker stop.
func (c *Consumer[Message]) RefreshHeartbeat(ctx context.Context, state health.State) error {
	if err := c.heartbeat.Write(ctx, state); err != nil {
		return fmt.Errorf("worker: write %s heartbeat: %w", state, err)
	}
	now, err := c.system.NowUTC()
	if err != nil {
		return fmt.Errorf("worker: read metric clock: %w", err)
	}
	attributes := make(map[string]any, len(c.identityAttributes)+1)
	for name, value := range c.identityAttributes {
		attributes[name] = value
	}
	attributes["atomi.worker.state"] = string(state)
	value := float64(0)
	if state == health.StateHealthy {
		value = 1
	}
	metric := interfaces.NewMetricRecord(
		now,
		"atomi.worker.health",
		interfaces.MetricKindGauge,
		value,
		nil,
		attributes,
	)
	if err := c.metrics.Emit(metric); err != nil {
		_ = c.EmitLog(interfaces.LogLevelWarning, "worker health metric failed", attributes, err)
	}
	return nil
}

// ProcessEnvelope validates and handles one envelope. Invalid messages are
// acknowledged so poison data cannot block the group; domain failures remain
// pending for later reclaim.
func (c *Consumer[Message]) ProcessEnvelope(ctx context.Context, envelope Envelope) bool {
	if len([]byte(envelope.Payload)) > c.maxMessageBytes {
		_ = c.EmitLog(interfaces.LogLevelError, "invalid worker message", map[string]any{"streamId": envelope.ID}, errors.New("message exceeds configured limit"))
		return true
	}
	message, err := c.decoder.Decode(ctx, envelope.Payload)
	if err != nil {
		_ = c.EmitLog(interfaces.LogLevelError, "invalid worker message", map[string]any{"streamId": envelope.ID}, err)
		return true
	}
	result, err := c.handler.Handle(ctx, message)
	if err != nil {
		_ = c.EmitLog(interfaces.LogLevelError, "message handling failed", map[string]any{"streamId": envelope.ID}, err)
		return false
	}
	_ = c.EmitLog(interfaces.LogLevelInfo, "message handled", map[string]any{
		"streamId":  envelope.ID,
		"messageId": result.MessageID,
		"inserted":  result.Inserted,
		"objectKey": result.ObjectKey,
	}, nil)
	return true
}

// ProcessBatch handles and acknowledges one batch, returning the number of
// entries Redis reported as acknowledged.
func (c *Consumer[Message]) ProcessBatch(ctx context.Context, envelopes []Envelope) (int64, error) {
	acknowledged := int64(0)
	for _, envelope := range envelopes {
		if !c.ProcessEnvelope(ctx, envelope) {
			continue
		}
		count, err := c.transport.Acknowledge(ctx, envelope.ID)
		if err != nil {
			return acknowledged, fmt.Errorf("worker: acknowledge stream entry %q: %w", envelope.ID, err)
		}
		acknowledged += count
	}
	return acknowledged, nil
}

// Run starts the consumer, reclaims pending entries, and consumes until one
// iteration completes or ctx is cancelled.
func (c *Consumer[Message]) Run(ctx context.Context, once bool) error { //nolint:revive // The CLI's --once flag intentionally selects one loop iteration.
	if err := c.RefreshHeartbeat(ctx, health.StateStarting); err != nil {
		return err
	}
	if err := c.transport.EnsureGroup(ctx); err != nil {
		return fmt.Errorf("worker: ensure consumer group: %w", err)
	}
	pending, err := c.transport.ReclaimPending(ctx)
	if err != nil {
		return fmt.Errorf("worker: reclaim pending entries: %w", err)
	}
	if _, err := c.ProcessBatch(ctx, pending); err != nil {
		return err
	}
	for {
		envelopes, err := c.transport.Consume(ctx)
		if err != nil {
			return fmt.Errorf("worker: consume stream entries: %w", err)
		}
		if _, err := c.ProcessBatch(ctx, envelopes); err != nil {
			return err
		}
		if err := c.RefreshHeartbeat(ctx, health.StateHealthy); err != nil {
			return err
		}
		if once {
			return nil
		}
		select {
		case <-ctx.Done():
			if err := c.RefreshHeartbeat(context.WithoutCancel(ctx), health.StateStopping); err != nil {
				return err
			}
			return nil
		default:
		}
	}
}
