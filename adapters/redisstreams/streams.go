// Package redisstreams adapts Redis Streams to the worker transport port.
package redisstreams

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/AtomiCloud/diene.go-consumer/adapters/tracing"
	"github.com/AtomiCloud/diene.go-consumer/lib/worker"
	goredis "github.com/redis/go-redis/v9"
)

// PayloadField is the Redis Stream field containing the encoded message.
const PayloadField = "payload"

// Config controls one Redis Streams consumer group.
type Config struct {
	Stream    string
	Group     string
	Consumer  string
	Block     time.Duration
	Idle      time.Duration
	BatchSize int64
}

// StreamAPI is the go-redis streams surface used by Transport.
type StreamAPI interface {
	XGroupCreateMkStream(ctx context.Context, stream, group, start string) *goredis.StatusCmd
	XAdd(ctx context.Context, args *goredis.XAddArgs) *goredis.StringCmd
	XReadGroup(ctx context.Context, args *goredis.XReadGroupArgs) *goredis.XStreamSliceCmd
	XAutoClaim(ctx context.Context, args *goredis.XAutoClaimArgs) *goredis.XAutoClaimCmd
	XAck(ctx context.Context, stream, group string, ids ...string) *goredis.IntCmd
}

// Transport is an instrumented Redis Streams consumer and publisher.
type Transport struct {
	client StreamAPI
	config Config
	tracer *tracing.Tracer
}

// New constructs a Redis Streams transport.
func New(client StreamAPI, config Config, tracer *tracing.Tracer) (*Transport, error) {
	if client == nil {
		return nil, errors.New("redis streams: client is required")
	}
	if tracer == nil {
		return nil, errors.New("redis streams: tracer is required")
	}
	if err := validateConfig(config); err != nil {
		return nil, err
	}
	return &Transport{client: client, config: config, tracer: tracer}, nil
}

// EnsureGroup creates the configured group and stream when absent.
func (t *Transport) EnsureGroup(ctx context.Context) error {
	span, err := t.tracer.Start("redis_streams.ensure_group", t.attributes())
	if err != nil {
		return err
	}
	operationErr := t.client.XGroupCreateMkStream(ctx, t.config.Stream, t.config.Group, "0").Err()
	if operationErr != nil && strings.Contains(operationErr.Error(), "BUSYGROUP") {
		operationErr = nil
	}
	return span.End(operationErr)
}

// Publish appends an encoded payload and returns its stream entry id.
func (t *Transport) Publish(ctx context.Context, payload string) (string, error) {
	span, err := t.tracer.Start("redis_streams.publish", t.attributes())
	if err != nil {
		return "", err
	}
	id, operationErr := t.client.XAdd(ctx, &goredis.XAddArgs{
		Stream: t.config.Stream,
		Values: map[string]any{PayloadField: payload},
	}).Result()
	if endErr := span.End(operationErr); endErr != nil {
		return "", endErr
	}
	return id, nil
}

// Add is an alias for Publish used by message-driven SIT setup.
func (t *Transport) Add(ctx context.Context, payload string) (string, error) {
	return t.Publish(ctx, payload)
}

// ReclaimPending claims one batch whose idle time exceeds Config.Idle.
func (t *Transport) ReclaimPending(ctx context.Context) ([]worker.Envelope, error) {
	span, err := t.tracer.Start("redis_streams.reclaim", t.attributes())
	if err != nil {
		return nil, err
	}
	messages, _, operationErr := t.client.XAutoClaim(ctx, &goredis.XAutoClaimArgs{
		Stream:   t.config.Stream,
		Group:    t.config.Group,
		Consumer: t.config.Consumer,
		MinIdle:  t.config.Idle,
		Start:    "0-0",
		Count:    t.config.BatchSize,
	}).Result()
	if errors.Is(operationErr, goredis.Nil) {
		operationErr = nil
	}
	if operationErr != nil {
		return nil, span.End(operationErr)
	}
	envelopes, decodeErr := decodeMessages(messages)
	if endErr := span.End(decodeErr); endErr != nil {
		return nil, endErr
	}
	return envelopes, nil
}

// Consume reads one batch of new messages through the configured group.
func (t *Transport) Consume(ctx context.Context) ([]worker.Envelope, error) {
	span, err := t.tracer.Start("redis_streams.consume", t.attributes())
	if err != nil {
		return nil, err
	}
	streams, operationErr := t.client.XReadGroup(ctx, &goredis.XReadGroupArgs{
		Group:    t.config.Group,
		Consumer: t.config.Consumer,
		Streams:  []string{t.config.Stream, ">"},
		Count:    t.config.BatchSize,
		Block:    t.config.Block,
	}).Result()
	if errors.Is(operationErr, goredis.Nil) {
		operationErr = nil
	}
	if operationErr != nil {
		return nil, span.End(operationErr)
	}
	messages := make([]goredis.XMessage, 0)
	for _, stream := range streams {
		messages = append(messages, stream.Messages...)
	}
	envelopes, decodeErr := decodeMessages(messages)
	if endErr := span.End(decodeErr); endErr != nil {
		return nil, endErr
	}
	return envelopes, nil
}

// Acknowledge marks one stream entry as processed.
func (t *Transport) Acknowledge(ctx context.Context, id string) (int64, error) {
	if strings.TrimSpace(id) == "" {
		return 0, errors.New("redis streams: message id is required")
	}
	span, err := t.tracer.Start("redis_streams.acknowledge", t.attributes())
	if err != nil {
		return 0, err
	}
	acknowledged, operationErr := t.client.XAck(ctx, t.config.Stream, t.config.Group, id).Result()
	if endErr := span.End(operationErr); endErr != nil {
		return 0, endErr
	}
	return acknowledged, nil
}

func (t *Transport) attributes() map[string]any {
	return map[string]any{
		"messaging.system":           "redis",
		"messaging.destination.name": t.config.Stream,
		"messaging.consumer.group":   t.config.Group,
	}
}

func decodeMessages(messages []goredis.XMessage) ([]worker.Envelope, error) {
	envelopes := make([]worker.Envelope, 0, len(messages))
	for _, message := range messages {
		value, found := message.Values[PayloadField]
		if !found {
			return nil, fmt.Errorf("redis streams: entry %q has no %q field", message.ID, PayloadField)
		}
		var payload string
		switch typed := value.(type) {
		case string:
			payload = typed
		case []byte:
			payload = string(typed)
		default:
			return nil, fmt.Errorf(
				"redis streams: entry %q field %q has unsupported type %T",
				message.ID,
				PayloadField,
				value,
			)
		}
		envelopes = append(envelopes, worker.Envelope{ID: message.ID, Payload: payload})
	}
	return envelopes, nil
}

func validateConfig(config Config) error {
	switch {
	case strings.TrimSpace(config.Stream) == "":
		return errors.New("redis streams: stream is required")
	case strings.TrimSpace(config.Group) == "":
		return errors.New("redis streams: group is required")
	case strings.TrimSpace(config.Consumer) == "":
		return errors.New("redis streams: consumer is required")
	case config.Block <= 0:
		return errors.New("redis streams: block duration must be positive")
	case config.Idle < 0:
		return errors.New("redis streams: idle duration must not be negative")
	case config.BatchSize < 1:
		return errors.New("redis streams: batch size must be positive")
	default:
		return nil
	}
}
