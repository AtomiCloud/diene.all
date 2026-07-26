package worker_test

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-consumer/lib/health"
	"github.com/AtomiCloud/diene.go-consumer/lib/worker"
	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
	interfacestest "github.com/AtomiCloud/diene.go-interfaces/testhelper"
	oteltest "github.com/AtomiCloud/diene.go-otel/testhelper"
)

type transportResult struct {
	envelopes []worker.Envelope
	err       error
}

type acknowledgeResult struct {
	count int64
	err   error
}

type transportFake struct {
	ensureErr        error
	reclaimResult    transportResult
	consumeResults   []transportResult
	acknowledgements map[string]acknowledgeResult
	ensureCalls      int
	reclaimCalls     int
	consumeCalls     int
	acknowledgedIDs  []string
	onConsume        func(int)
}

func (f *transportFake) EnsureGroup(context.Context) error {
	f.ensureCalls++
	return f.ensureErr
}

func (f *transportFake) ReclaimPending(context.Context) ([]worker.Envelope, error) {
	f.reclaimCalls++
	return append([]worker.Envelope(nil), f.reclaimResult.envelopes...), f.reclaimResult.err
}

func (f *transportFake) Consume(context.Context) ([]worker.Envelope, error) {
	f.consumeCalls++
	if f.onConsume != nil {
		f.onConsume(f.consumeCalls)
	}
	if f.consumeCalls > len(f.consumeResults) {
		return nil, nil
	}
	result := f.consumeResults[f.consumeCalls-1]
	return append([]worker.Envelope(nil), result.envelopes...), result.err
}

func (f *transportFake) Acknowledge(_ context.Context, id string) (int64, error) {
	f.acknowledgedIDs = append(f.acknowledgedIDs, id)
	result, ok := f.acknowledgements[id]
	if !ok {
		return 1, nil
	}
	return result.count, result.err
}

type decodeResult struct {
	message string
	err     error
}

type decoderFake struct {
	results map[string]decodeResult
	calls   []string
}

func (f *decoderFake) Decode(_ context.Context, payload string) (string, error) {
	f.calls = append(f.calls, payload)
	result, ok := f.results[payload]
	if !ok {
		return payload, nil
	}
	return result.message, result.err
}

type handleResult struct {
	result worker.HandleResult
	err    error
}

type handlerFake struct {
	results map[string]handleResult
	calls   []string
}

func (f *handlerFake) Handle(_ context.Context, message string) (worker.HandleResult, error) {
	f.calls = append(f.calls, message)
	result, ok := f.results[message]
	if !ok {
		return worker.HandleResult{MessageID: message, Inserted: true, ObjectKey: "objects/" + message}, nil
	}
	return result.result, result.err
}

type heartbeatFake struct {
	states        []health.State
	contextErrors []error
	results       []error
}

func (f *heartbeatFake) Write(ctx context.Context, state health.State) error {
	f.states = append(f.states, state)
	f.contextErrors = append(f.contextErrors, ctx.Err())
	index := len(f.states) - 1
	if index >= len(f.results) {
		return nil
	}
	return f.results[index]
}

type consumerFixture struct {
	subject   *worker.Consumer[string]
	transport *transportFake
	decoder   *decoderFake
	handler   *handlerFake
	heartbeat *heartbeatFake
	system    *interfacestest.InMemorySystem
	logger    *oteltest.InMemoryLoggerSink
	metrics   *oteltest.InMemoryMetricsCollector
}

func newConsumerFixture(t *testing.T) *consumerFixture {
	t.Helper()
	transport := &transportFake{acknowledgements: map[string]acknowledgeResult{}}
	decoder := &decoderFake{results: map[string]decodeResult{}}
	handler := &handlerFake{results: map[string]handleResult{}}
	heartbeat := &heartbeatFake{}
	system := interfacestest.NewInMemorySystem(interfacestest.InMemorySystemOptions{
		Now: time.Date(2026, time.July, 26, 22, 0, 0, 0, time.UTC),
	})
	logger := oteltest.NewInMemoryLoggerSink()
	metrics := oteltest.NewInMemoryMetricsCollector()
	subject, err := worker.NewConsumer(worker.Options[string]{
		Transport:          transport,
		Decoder:            decoder,
		Handler:            handler,
		Heartbeat:          heartbeat,
		System:             system,
		Logger:             logger,
		Metrics:            metrics,
		MaxMessageBytes:    64,
		IdentityAttributes: map[string]string{"atomi.consumer.name": "unit"},
	})
	if err != nil {
		t.Fatalf("NewConsumer() error = %v", err)
	}
	return &consumerFixture{
		subject: subject, transport: transport, decoder: decoder, handler: handler,
		heartbeat: heartbeat, system: system, logger: logger, metrics: metrics,
	}
}

func validOptions() worker.Options[string] {
	return worker.Options[string]{
		Transport:          &transportFake{acknowledgements: map[string]acknowledgeResult{}},
		Decoder:            &decoderFake{results: map[string]decodeResult{}},
		Handler:            &handlerFake{results: map[string]handleResult{}},
		Heartbeat:          &heartbeatFake{},
		System:             interfacestest.NewInMemorySystem(interfacestest.InMemorySystemOptions{}),
		Logger:             oteltest.NewInMemoryLoggerSink(),
		Metrics:            oteltest.NewInMemoryMetricsCollector(),
		MaxMessageBytes:    1,
		IdentityAttributes: map[string]string{"identity": "original"},
	}
}

func TestNewConsumerValidatesOptions(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name   string
		change func(*worker.Options[string])
		want   string
	}{
		{"transport", func(options *worker.Options[string]) { options.Transport = nil }, "transport is required"},
		{"decoder", func(options *worker.Options[string]) { options.Decoder = nil }, "decoder is required"},
		{"handler", func(options *worker.Options[string]) { options.Handler = nil }, "handler is required"},
		{"heartbeat", func(options *worker.Options[string]) { options.Heartbeat = nil }, "heartbeat is required"},
		{"system", func(options *worker.Options[string]) { options.System = nil }, "system is required"},
		{"logger", func(options *worker.Options[string]) { options.Logger = nil }, "logger is required"},
		{"metrics", func(options *worker.Options[string]) { options.Metrics = nil }, "metrics collector is required"},
		{"message size", func(options *worker.Options[string]) { options.MaxMessageBytes = 0 }, "max message bytes must be positive"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			options := validOptions()
			test.change(&options)
			if _, err := worker.NewConsumer(options); err == nil || !strings.Contains(err.Error(), test.want) {
				t.Fatalf("NewConsumer() error = %v, want containing %q", err, test.want)
			}
		})
	}
}

func TestNewConsumerOwnsIdentityAttributes(t *testing.T) {
	t.Parallel()

	options := validOptions()
	attributes := options.IdentityAttributes
	subject, err := worker.NewConsumer(options)
	if err != nil {
		t.Fatalf("NewConsumer() error = %v", err)
	}
	attributes["identity"] = "mutated"
	if err := subject.RefreshHeartbeat(context.Background(), health.StateHealthy); err != nil {
		t.Fatalf("RefreshHeartbeat() error = %v", err)
	}
	records := options.Metrics.(*oteltest.InMemoryMetricsCollector).Records()
	if len(records) != 1 || records[0].Attributes["identity"] != "original" {
		t.Fatalf("metric records = %#v", records)
	}
}

func TestEmitLogRecordsStructuredErrorsAndPlainMessages(t *testing.T) {
	t.Parallel()

	fixture := newConsumerFixture(t)
	want := errors.New("handler unavailable")
	if err := fixture.subject.EmitLog(interfaces.LogLevelError, "failed", map[string]any{"id": "one"}, want); err != nil {
		t.Fatalf("EmitLog() error = %v", err)
	}
	if err := fixture.subject.EmitLog(interfaces.LogLevelInfo, "ready", nil, nil); err != nil {
		t.Fatalf("EmitLog() error = %v", err)
	}
	records := fixture.logger.Records()
	if len(records) != 2 || records[0].Error == nil || *records[0].Error != want.Error() || records[1].Error != nil {
		t.Fatalf("log records = %#v", records)
	}
	if records[0].Level != interfaces.LogLevelError || records[0].Message != "failed" || records[0].Attributes["id"] != "one" {
		t.Fatalf("first log record = %#v", records[0])
	}
}

func TestEmitLogReturnsClockAndSinkFailures(t *testing.T) {
	t.Parallel()

	t.Run("clock", func(t *testing.T) {
		t.Parallel()
		fixture := newConsumerFixture(t)
		want := errors.New("clock unavailable")
		fixture.system.EnqueueClockResult(time.Time{}, want)
		if err := fixture.subject.EmitLog(interfaces.LogLevelInfo, "message", nil, nil); !errors.Is(err, want) {
			t.Fatalf("EmitLog() error = %v, want wrapping %v", err, want)
		}
	})
	t.Run("sink", func(t *testing.T) {
		t.Parallel()
		fixture := newConsumerFixture(t)
		want := errors.New("sink unavailable")
		fixture.logger.EnqueueResult(want)
		if err := fixture.subject.EmitLog(interfaces.LogLevelInfo, "message", nil, nil); !errors.Is(err, want) {
			t.Fatalf("EmitLog() error = %v, want wrapping %v", err, want)
		}
	})
}

func TestRefreshHeartbeatEmitsLifecycleMetrics(t *testing.T) {
	t.Parallel()

	tests := map[string]struct {
		state health.State
		value float64
	}{
		"starting": {health.StateStarting, 0},
		"healthy":  {health.StateHealthy, 1},
		"stopping": {health.StateStopping, 0},
	}
	for name, test := range tests {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			fixture := newConsumerFixture(t)
			if err := fixture.subject.RefreshHeartbeat(context.Background(), test.state); err != nil {
				t.Fatalf("RefreshHeartbeat() error = %v", err)
			}
			records := fixture.metrics.Records()
			if len(records) != 1 || records[0].Name != "atomi.worker.health" || records[0].Kind != interfaces.MetricKindGauge || records[0].Value != test.value {
				t.Fatalf("metric records = %#v", records)
			}
			if records[0].Attributes["atomi.worker.state"] != string(test.state) || records[0].Attributes["atomi.consumer.name"] != "unit" {
				t.Fatalf("metric attributes = %#v", records[0].Attributes)
			}
			if len(fixture.heartbeat.states) != 1 || fixture.heartbeat.states[0] != test.state {
				t.Fatalf("heartbeat states = %#v", fixture.heartbeat.states)
			}
		})
	}
}

func TestRefreshHeartbeatFailureHandling(t *testing.T) {
	t.Parallel()

	t.Run("heartbeat", func(t *testing.T) {
		t.Parallel()
		fixture := newConsumerFixture(t)
		want := errors.New("heartbeat unavailable")
		fixture.heartbeat.results = []error{want}
		if err := fixture.subject.RefreshHeartbeat(context.Background(), health.StateHealthy); !errors.Is(err, want) {
			t.Fatalf("RefreshHeartbeat() error = %v, want wrapping %v", err, want)
		}
		if len(fixture.metrics.Records()) != 0 {
			t.Fatal("metric emitted after heartbeat failure")
		}
	})
	t.Run("clock", func(t *testing.T) {
		t.Parallel()
		fixture := newConsumerFixture(t)
		want := errors.New("clock unavailable")
		fixture.system.EnqueueClockResult(time.Time{}, want)
		if err := fixture.subject.RefreshHeartbeat(context.Background(), health.StateHealthy); !errors.Is(err, want) {
			t.Fatalf("RefreshHeartbeat() error = %v, want wrapping %v", err, want)
		}
	})
	t.Run("metric is best effort", func(t *testing.T) {
		t.Parallel()
		fixture := newConsumerFixture(t)
		fixture.metrics.EnqueueResult(errors.New("metric unavailable"))
		if err := fixture.subject.RefreshHeartbeat(context.Background(), health.StateHealthy); err != nil {
			t.Fatalf("RefreshHeartbeat() error = %v", err)
		}
		logs := fixture.logger.Records()
		if len(logs) != 1 || logs[0].Level != interfaces.LogLevelWarning || logs[0].Message != "worker health metric failed" {
			t.Fatalf("warning logs = %#v", logs)
		}
	})
}

func TestProcessEnvelopeOutcomes(t *testing.T) {
	t.Parallel()

	t.Run("oversized payload is acknowledged", func(t *testing.T) {
		t.Parallel()
		fixture := newConsumerFixture(t)
		if !fixture.subject.ProcessEnvelope(context.Background(), worker.Envelope{ID: "1-0", Payload: strings.Repeat("x", 65)}) {
			t.Fatal("ProcessEnvelope() = false, want true")
		}
		if len(fixture.decoder.calls) != 0 {
			t.Fatalf("decoder calls = %#v", fixture.decoder.calls)
		}
	})
	t.Run("decode failure is acknowledged", func(t *testing.T) {
		t.Parallel()
		fixture := newConsumerFixture(t)
		fixture.decoder.results["bad"] = decodeResult{err: errors.New("invalid payload")}
		if !fixture.subject.ProcessEnvelope(context.Background(), worker.Envelope{ID: "2-0", Payload: "bad"}) {
			t.Fatal("ProcessEnvelope() = false, want true")
		}
	})
	t.Run("handler failure remains pending", func(t *testing.T) {
		t.Parallel()
		fixture := newConsumerFixture(t)
		fixture.handler.results["message"] = handleResult{err: errors.New("side effect failed")}
		if fixture.subject.ProcessEnvelope(context.Background(), worker.Envelope{ID: "3-0", Payload: "message"}) {
			t.Fatal("ProcessEnvelope() = true, want false")
		}
	})
	t.Run("success is acknowledged", func(t *testing.T) {
		t.Parallel()
		fixture := newConsumerFixture(t)
		fixture.handler.results["message"] = handleResult{result: worker.HandleResult{MessageID: "domain-id", Inserted: true, ObjectKey: "objects/domain-id"}}
		if !fixture.subject.ProcessEnvelope(context.Background(), worker.Envelope{ID: "4-0", Payload: "message"}) {
			t.Fatal("ProcessEnvelope() = false, want true")
		}
		logs := fixture.logger.Records()
		if len(logs) != 1 || logs[0].Message != "message handled" || logs[0].Attributes["messageId"] != "domain-id" {
			t.Fatalf("success logs = %#v", logs)
		}
	})
}

func TestProcessBatchAcknowledgesOnlyCompletedMessages(t *testing.T) {
	t.Parallel()

	fixture := newConsumerFixture(t)
	fixture.decoder.results["bad"] = decodeResult{err: errors.New("invalid")}
	fixture.handler.results["retry"] = handleResult{err: errors.New("retry")}
	fixture.transport.acknowledgements["1-0"] = acknowledgeResult{count: 2}
	fixture.transport.acknowledgements["3-0"] = acknowledgeResult{count: 3}
	actual, err := fixture.subject.ProcessBatch(context.Background(), []worker.Envelope{
		{ID: "1-0", Payload: "bad"},
		{ID: "2-0", Payload: "retry"},
		{ID: "3-0", Payload: "ok"},
	})
	if err != nil {
		t.Fatalf("ProcessBatch() error = %v", err)
	}
	if actual != 5 || strings.Join(fixture.transport.acknowledgedIDs, ",") != "1-0,3-0" {
		t.Fatalf("ProcessBatch() = %d, acknowledgements = %#v", actual, fixture.transport.acknowledgedIDs)
	}
}

func TestProcessBatchReturnsPartialCountOnAcknowledgeFailure(t *testing.T) {
	t.Parallel()

	fixture := newConsumerFixture(t)
	want := errors.New("ack unavailable")
	fixture.transport.acknowledgements["1-0"] = acknowledgeResult{count: 2}
	fixture.transport.acknowledgements["2-0"] = acknowledgeResult{err: want}
	actual, err := fixture.subject.ProcessBatch(context.Background(), []worker.Envelope{
		{ID: "1-0", Payload: "one"},
		{ID: "2-0", Payload: "two"},
	})
	if actual != 2 || !errors.Is(err, want) {
		t.Fatalf("ProcessBatch() = (%d, %v), want (2, wrapping %v)", actual, err, want)
	}
}

func TestRunOnceProcessesPendingAndNewMessages(t *testing.T) {
	t.Parallel()

	fixture := newConsumerFixture(t)
	fixture.transport.reclaimResult.envelopes = []worker.Envelope{{ID: "1-0", Payload: "pending"}}
	fixture.transport.consumeResults = []transportResult{{envelopes: []worker.Envelope{{ID: "2-0", Payload: "new"}}}}
	if err := fixture.subject.Run(context.Background(), true); err != nil {
		t.Fatalf("Run() error = %v", err)
	}
	if fixture.transport.ensureCalls != 1 || fixture.transport.reclaimCalls != 1 || fixture.transport.consumeCalls != 1 {
		t.Fatalf("transport calls = ensure %d, reclaim %d, consume %d", fixture.transport.ensureCalls, fixture.transport.reclaimCalls, fixture.transport.consumeCalls)
	}
	if strings.Join(fixture.transport.acknowledgedIDs, ",") != "1-0,2-0" {
		t.Fatalf("acknowledged IDs = %#v", fixture.transport.acknowledgedIDs)
	}
	if len(fixture.heartbeat.states) != 2 || fixture.heartbeat.states[0] != health.StateStarting || fixture.heartbeat.states[1] != health.StateHealthy {
		t.Fatalf("heartbeat states = %#v", fixture.heartbeat.states)
	}
}

func TestRunReturnsEveryStageFailure(t *testing.T) {
	t.Parallel()

	want := errors.New("stage unavailable")
	tests := []struct {
		name      string
		configure func(*consumerFixture)
	}{
		{"starting heartbeat", func(fixture *consumerFixture) { fixture.heartbeat.results = []error{want} }},
		{"ensure group", func(fixture *consumerFixture) { fixture.transport.ensureErr = want }},
		{"reclaim", func(fixture *consumerFixture) { fixture.transport.reclaimResult.err = want }},
		{"pending acknowledgement", func(fixture *consumerFixture) {
			fixture.transport.reclaimResult.envelopes = []worker.Envelope{{ID: "pending", Payload: "message"}}
			fixture.transport.acknowledgements["pending"] = acknowledgeResult{err: want}
		}},
		{"consume", func(fixture *consumerFixture) { fixture.transport.consumeResults = []transportResult{{err: want}} }},
		{"consumed acknowledgement", func(fixture *consumerFixture) {
			fixture.transport.consumeResults = []transportResult{{envelopes: []worker.Envelope{{ID: "new", Payload: "message"}}}}
			fixture.transport.acknowledgements["new"] = acknowledgeResult{err: want}
		}},
		{"healthy heartbeat", func(fixture *consumerFixture) { fixture.heartbeat.results = []error{nil, want} }},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			fixture := newConsumerFixture(t)
			test.configure(fixture)
			if err := fixture.subject.Run(context.Background(), true); !errors.Is(err, want) {
				t.Fatalf("Run() error = %v, want wrapping %v", err, want)
			}
		})
	}
}

func TestRunContinuousWritesStoppingHeartbeatOnCancellation(t *testing.T) {
	t.Parallel()

	fixture := newConsumerFixture(t)
	ctx, cancel := context.WithCancel(context.Background())
	fixture.transport.consumeResults = []transportResult{{}}
	fixture.transport.onConsume = func(int) { cancel() }
	if err := fixture.subject.Run(ctx, false); err != nil {
		t.Fatalf("Run() error = %v", err)
	}
	want := []health.State{health.StateStarting, health.StateHealthy, health.StateStopping}
	if len(fixture.heartbeat.states) != len(want) {
		t.Fatalf("heartbeat states = %#v", fixture.heartbeat.states)
	}
	for index, state := range want {
		if fixture.heartbeat.states[index] != state {
			t.Fatalf("heartbeat states = %#v", fixture.heartbeat.states)
		}
	}
	if fixture.heartbeat.contextErrors[2] != nil {
		t.Fatalf("stopping heartbeat context error = %v", fixture.heartbeat.contextErrors[2])
	}
}

func TestRunContinuousReturnsStoppingHeartbeatFailure(t *testing.T) {
	t.Parallel()

	fixture := newConsumerFixture(t)
	want := errors.New("stopping unavailable")
	fixture.heartbeat.results = []error{nil, nil, want}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	fixture.transport.consumeResults = []transportResult{{}}
	if err := fixture.subject.Run(ctx, false); !errors.Is(err, want) {
		t.Fatalf("Run() error = %v, want wrapping %v", err, want)
	}
}
