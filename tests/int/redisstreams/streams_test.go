package redisstreams_test

import (
	"context"
	"errors"
	"testing"
	"time"

	redisadapter "github.com/AtomiCloud/diene.go-consumer/adapters/redis"
	"github.com/AtomiCloud/diene.go-consumer/adapters/redisstreams"
	"github.com/AtomiCloud/diene.go-consumer/adapters/tracing"
	interfaceshelper "github.com/AtomiCloud/diene.go-interfaces/testhelper"
	otelhelper "github.com/AtomiCloud/diene.go-otel/testhelper"
	standardhelper "github.com/AtomiCloud/diene.go-standard-config/testhelper"
	goredis "github.com/redis/go-redis/v9"
)

func TestTransportAgainstRedis(t *testing.T) {
	ctx := context.Background()
	started, err := standardhelper.StartKv(ctx, standardhelper.RedisOptions{})
	if err != nil {
		t.Fatalf("start Redis: %v", err)
	}
	t.Cleanup(func() { _ = started.Terminate(ctx) })
	tracer, emitter, _ := newTracer(t)
	redisClient, err := redisadapter.Open(started.Entry, tracer)
	if err != nil {
		t.Fatalf("open Redis: %v", err)
	}
	t.Cleanup(func() { _ = redisClient.Close() })
	transport, err := redisstreams.New(redisClient.Native(), validConfig(), tracer)
	if err != nil {
		t.Fatalf("construct transport: %v", err)
	}

	if err := transport.EnsureGroup(ctx); err != nil {
		t.Fatalf("create consumer group: %v", err)
	}
	if err := transport.EnsureGroup(ctx); err != nil {
		t.Fatalf("reuse consumer group: %v", err)
	}
	firstID, err := transport.Publish(ctx, `{"id":"one"}`)
	if err != nil || firstID == "" {
		t.Fatalf("publish: id=%q err=%v", firstID, err)
	}
	secondID, err := transport.Add(ctx, `{"id":"two"}`)
	if err != nil || secondID == "" {
		t.Fatalf("add: id=%q err=%v", secondID, err)
	}

	envelopes, err := transport.Consume(ctx)
	if err != nil || len(envelopes) != 2 {
		t.Fatalf("consume: envelopes=%v err=%v", envelopes, err)
	}
	pending, err := transport.ReclaimPending(ctx)
	if err != nil || len(pending) != 2 {
		t.Fatalf("reclaim: envelopes=%v err=%v", pending, err)
	}
	for _, envelope := range pending {
		acknowledged, acknowledgeErr := transport.Acknowledge(ctx, envelope.ID)
		if acknowledgeErr != nil || acknowledged != 1 {
			t.Fatalf("acknowledge %s: count=%d err=%v", envelope.ID, acknowledged, acknowledgeErr)
		}
	}
	if pending, err := transport.ReclaimPending(ctx); err != nil || len(pending) != 0 {
		t.Fatalf("expected no pending messages: envelopes=%v err=%v", pending, err)
	}
	if envelopes, err := transport.Consume(ctx); err != nil || len(envelopes) != 0 {
		t.Fatalf("expected no new messages: envelopes=%v err=%v", envelopes, err)
	}
	if len(emitter.Records()) < 10 {
		t.Fatalf("expected stream traces, got %d", len(emitter.Records()))
	}
}

func TestTransportValidation(t *testing.T) {
	t.Parallel()
	tracer, _, _ := newTracer(t)
	client := &fakeStreams{}
	if _, err := redisstreams.New(nil, validConfig(), tracer); err == nil {
		t.Fatal("expected missing client error")
	}
	if _, err := redisstreams.New(client, validConfig(), nil); err == nil {
		t.Fatal("expected missing tracer error")
	}
	tests := []struct {
		name   string
		mutate func(*redisstreams.Config)
	}{
		{"stream", func(config *redisstreams.Config) { config.Stream = "" }},
		{"group", func(config *redisstreams.Config) { config.Group = "" }},
		{"consumer", func(config *redisstreams.Config) { config.Consumer = "" }},
		{"block", func(config *redisstreams.Config) { config.Block = 0 }},
		{"idle", func(config *redisstreams.Config) { config.Idle = -time.Nanosecond }},
		{"batch", func(config *redisstreams.Config) { config.BatchSize = 0 }},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			config := validConfig()
			test.mutate(&config)
			if _, err := redisstreams.New(client, config, tracer); err == nil {
				t.Fatal("expected invalid config error")
			}
		})
	}
}

func TestTransportFailureAndDecodePaths(t *testing.T) {
	t.Parallel()
	ctx := context.Background()
	tracer, emitter, system := newTracer(t)
	driverErr := errors.New("driver failed")
	client := &fakeStreams{groupErr: driverErr}
	transport, err := redisstreams.New(client, validConfig(), tracer)
	if err != nil {
		t.Fatalf("construct transport: %v", err)
	}
	if err := transport.EnsureGroup(ctx); !errors.Is(err, driverErr) {
		t.Fatalf("expected group error, got %v", err)
	}
	client.groupErr = errors.New("BUSYGROUP Consumer Group name already exists")
	if err := transport.EnsureGroup(ctx); err != nil {
		t.Fatalf("busy group should be idempotent: %v", err)
	}

	client.publishErr = driverErr
	if _, err := transport.Publish(ctx, "payload"); !errors.Is(err, driverErr) {
		t.Fatalf("expected publish error, got %v", err)
	}
	client.publishErr = nil
	client.publishID = "1-0"
	emitErr := errors.New("emit failed")
	emitter.EnqueueResult(emitErr)
	if _, err := transport.Publish(ctx, "payload"); !errors.Is(err, emitErr) {
		t.Fatalf("expected publish emit error, got %v", err)
	}

	client.reclaimErr = driverErr
	if _, err := transport.ReclaimPending(ctx); !errors.Is(err, driverErr) {
		t.Fatalf("expected reclaim error, got %v", err)
	}
	client.reclaimErr = goredis.Nil
	if envelopes, err := transport.ReclaimPending(ctx); err != nil || len(envelopes) != 0 {
		t.Fatalf("expected empty nil reclaim: envelopes=%v err=%v", envelopes, err)
	}
	client.reclaimErr = nil
	client.reclaimed = []goredis.XMessage{{ID: "1-0", Values: map[string]any{redisstreams.PayloadField: []byte("bytes")}}}
	if envelopes, err := transport.ReclaimPending(ctx); err != nil || len(envelopes) != 1 || envelopes[0].Payload != "bytes" {
		t.Fatalf("unexpected byte reclaim: envelopes=%v err=%v", envelopes, err)
	}
	client.reclaimed = []goredis.XMessage{{ID: "1-0", Values: map[string]any{}}}
	if _, err := transport.ReclaimPending(ctx); err == nil {
		t.Fatal("expected missing payload error")
	}
	client.reclaimed = []goredis.XMessage{{ID: "1-0", Values: map[string]any{redisstreams.PayloadField: 7}}}
	if _, err := transport.ReclaimPending(ctx); err == nil {
		t.Fatal("expected unsupported payload error")
	}

	client.readErr = driverErr
	if _, err := transport.Consume(ctx); !errors.Is(err, driverErr) {
		t.Fatalf("expected consume error, got %v", err)
	}
	client.readErr = goredis.Nil
	if envelopes, err := transport.Consume(ctx); err != nil || len(envelopes) != 0 {
		t.Fatalf("expected empty nil consume: envelopes=%v err=%v", envelopes, err)
	}
	client.readErr = nil
	client.streams = []goredis.XStream{{Stream: "events", Messages: []goredis.XMessage{{
		ID: "2-0", Values: map[string]any{redisstreams.PayloadField: "text"},
	}}}}
	if envelopes, err := transport.Consume(ctx); err != nil || len(envelopes) != 1 || envelopes[0].Payload != "text" {
		t.Fatalf("unexpected consume: envelopes=%v err=%v", envelopes, err)
	}

	if _, err := transport.Acknowledge(ctx, " "); err == nil {
		t.Fatal("expected blank message id error")
	}
	client.ackErr = driverErr
	if _, err := transport.Acknowledge(ctx, "2-0"); !errors.Is(err, driverErr) {
		t.Fatalf("expected acknowledge error, got %v", err)
	}

	clockErr := errors.New("clock failed")
	system.EnqueueClockResult(readClock(t, system), clockErr)
	if err := transport.EnsureGroup(ctx); !errors.Is(err, clockErr) {
		t.Fatalf("expected clock error, got %v", err)
	}
}

func validConfig() redisstreams.Config {
	return redisstreams.Config{
		Stream: "events", Group: "workers", Consumer: "worker-one",
		Block: 5 * time.Millisecond, Idle: time.Nanosecond, BatchSize: 10,
	}
}

func newTracer(t *testing.T) (*tracing.Tracer, *otelhelper.InMemoryTraceEmitter, *interfaceshelper.InMemorySystem) {
	t.Helper()
	system := interfaceshelper.NewInMemorySystem(interfaceshelper.InMemorySystemOptions{})
	emitter := otelhelper.NewInMemoryTraceEmitter()
	tracer, err := tracing.New(system, emitter)
	if err != nil {
		t.Fatalf("construct tracer: %v", err)
	}
	return tracer, emitter, system
}

func readClock(t *testing.T, system *interfaceshelper.InMemorySystem) time.Time {
	t.Helper()
	now, err := system.NowUTC()
	if err != nil {
		t.Fatalf("read clock: %v", err)
	}
	return now
}

type fakeStreams struct {
	groupErr    error
	publishID   string
	publishErr  error
	streams     []goredis.XStream
	readErr     error
	reclaimed   []goredis.XMessage
	reclaimNext string
	reclaimErr  error
	acknowledge int64
	ackErr      error
}

func (f *fakeStreams) XGroupCreateMkStream(ctx context.Context, _, _, _ string) *goredis.StatusCmd {
	return goredis.NewStatusResult("OK", f.groupErr)
}

func (f *fakeStreams) XAdd(context.Context, *goredis.XAddArgs) *goredis.StringCmd {
	return goredis.NewStringResult(f.publishID, f.publishErr)
}

func (f *fakeStreams) XReadGroup(ctx context.Context, _ *goredis.XReadGroupArgs) *goredis.XStreamSliceCmd {
	command := goredis.NewXStreamSliceCmd(ctx)
	command.SetVal(f.streams)
	command.SetErr(f.readErr)
	return command
}

func (f *fakeStreams) XAutoClaim(ctx context.Context, _ *goredis.XAutoClaimArgs) *goredis.XAutoClaimCmd {
	command := goredis.NewXAutoClaimCmd(ctx)
	command.SetVal(f.reclaimed, f.reclaimNext)
	command.SetErr(f.reclaimErr)
	return command
}

func (f *fakeStreams) XAck(context.Context, string, string, ...string) *goredis.IntCmd {
	return goredis.NewIntResult(f.acknowledge, f.ackErr)
}
