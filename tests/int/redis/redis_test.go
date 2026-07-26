package redis_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
	redisadapter "github.com/AtomiCloud/diene.go-consumer/adapters/redis"
	"github.com/AtomiCloud/diene.go-consumer/adapters/tracing"
	interfaceshelper "github.com/AtomiCloud/diene.go-interfaces/testhelper"
	otelhelper "github.com/AtomiCloud/diene.go-otel/testhelper"
	"github.com/AtomiCloud/diene.go-standard-config/lib/standardconfig"
	standardhelper "github.com/AtomiCloud/diene.go-standard-config/testhelper"
	goredis "github.com/redis/go-redis/v9"
)

func TestClientAgainstRedis(t *testing.T) {
	ctx := context.Background()
	started, err := standardhelper.StartKv(ctx, standardhelper.RedisOptions{})
	if err != nil {
		t.Fatalf("start Redis: %v", err)
	}
	t.Cleanup(func() {
		if terminateErr := started.Terminate(ctx); terminateErr != nil {
			t.Errorf("terminate Redis: %v", terminateErr)
		}
	})

	tracer, emitter, _ := newTracer(t)
	client, err := redisadapter.Open(started.Entry, tracer)
	if err != nil {
		t.Fatalf("open adapter: %v", err)
	}
	t.Cleanup(func() {
		if closeErr := client.Close(); closeErr != nil {
			t.Errorf("close adapter: %v", closeErr)
		}
	})
	if client.Native() == nil {
		t.Fatal("expected native client")
	}
	if err := client.Ping(ctx); err != nil {
		t.Fatalf("ping: %v", err)
	}
	if value, found, err := client.Get(ctx, "missing"); err != nil || found || value != "" {
		t.Fatalf("unexpected missing result: value=%q found=%t err=%v", value, found, err)
	}
	if err := client.Set(ctx, "empty", "", 0); err != nil {
		t.Fatalf("set empty value: %v", err)
	}
	if value, found, err := client.Get(ctx, "empty"); err != nil || !found || value != "" {
		t.Fatalf("unexpected empty result: value=%q found=%t err=%v", value, found, err)
	}
	stored, err := client.SetIfAbsent(ctx, "marker", "one")
	if err != nil || !stored {
		t.Fatalf("set absent marker: stored=%t err=%v", stored, err)
	}
	stored, err = client.SetIfAbsent(ctx, "marker", "two")
	if err != nil || stored {
		t.Fatalf("set existing marker: stored=%t err=%v", stored, err)
	}
	deleted, err := client.Delete(ctx, "marker")
	if err != nil || deleted != 1 {
		t.Fatalf("delete marker: deleted=%d err=%v", deleted, err)
	}
	if deleted, err := client.Delete(ctx); err != nil || deleted != 0 {
		t.Fatalf("empty delete: deleted=%d err=%v", deleted, err)
	}
	if len(emitter.Records()) < 7 {
		t.Fatalf("expected Redis traces, got %d", len(emitter.Records()))
	}
}

func TestTokenStoreAgainstRedis(t *testing.T) {
	ctx := context.Background()
	started, err := standardhelper.StartKv(ctx, standardhelper.RedisOptions{})
	if err != nil {
		t.Fatalf("start Redis: %v", err)
	}
	t.Cleanup(func() { _ = started.Terminate(ctx) })
	tracer, _, _ := newTracer(t)
	client, err := redisadapter.Open(started.Entry, tracer)
	if err != nil {
		t.Fatalf("open adapter: %v", err)
	}
	t.Cleanup(func() { _ = client.Close() })
	store, err := redisadapter.NewTokenStore(client)
	if err != nil {
		t.Fatalf("construct token store: %v", err)
	}

	if token, found, err := store.Get(ctx, "missing-token"); err != nil || found || token.Value != "" {
		t.Fatalf("unexpected missing token: token=%#v found=%t err=%v", token, found, err)
	}
	now := time.Now().UTC().Truncate(time.Second)
	token := authengine.AccessToken{
		Value: "bearer", Resource: "backend", Scopes: []string{"read"},
		IssuedAt: now, ExpiresAt: now.Add(time.Hour),
	}
	if err := store.Set(ctx, "token", token, time.Hour); err != nil {
		t.Fatalf("set token: %v", err)
	}
	loaded, found, err := store.Get(ctx, "token")
	if err != nil || !found || loaded.Value != token.Value || !loaded.ExpiresAt.Equal(token.ExpiresAt) {
		t.Fatalf("unexpected loaded token: token=%#v found=%t err=%v", loaded, found, err)
	}
	if err := store.Delete(ctx, "token"); err != nil {
		t.Fatalf("delete token: %v", err)
	}
	if _, found, err := store.Get(ctx, "token"); err != nil || found {
		t.Fatalf("expected deleted token: found=%t err=%v", found, err)
	}

	if err := client.Set(ctx, "invalid-token", "not-json", 0); err != nil {
		t.Fatalf("seed invalid token: %v", err)
	}
	if _, _, err := store.Get(ctx, "invalid-token"); err == nil {
		t.Fatal("expected invalid token decoding error")
	}
	invalidTime := time.Date(10000, 1, 1, 0, 0, 0, 0, time.UTC)
	if err := store.Set(ctx, "invalid-time", authengine.AccessToken{IssuedAt: invalidTime}, time.Minute); err == nil {
		t.Fatal("expected token encoding error")
	}
}

func TestClientValidationAndDriverFailures(t *testing.T) {
	t.Parallel()
	ctx := context.Background()
	tracer, emitter, system := newTracer(t)
	valid := standardconfig.RedisEntry{Host: "redis.invalid", Port: 6379, DB: 0}
	for _, entry := range []standardconfig.RedisEntry{
		{Port: 6379},
		{Host: "redis.invalid", Port: 0},
		{Host: "redis.invalid", Port: 65536},
		{Host: "redis.invalid", Port: 6379, DB: -1},
	} {
		if _, err := redisadapter.Open(entry, tracer); err == nil {
			t.Fatalf("expected invalid entry error for %#v", entry)
		}
	}
	tlsEntry := valid
	tlsEntry.TLS = true
	tlsClient, err := redisadapter.Open(tlsEntry, tracer)
	if err != nil {
		t.Fatalf("construct TLS client: %v", err)
	}
	if err := tlsClient.Close(); err != nil {
		t.Fatalf("close TLS client: %v", err)
	}

	if _, err := redisadapter.New(nil, tracer); err == nil {
		t.Fatal("expected missing driver error")
	}
	if _, err := redisadapter.New(&fakeCommands{}, nil); err == nil {
		t.Fatal("expected missing tracer error")
	}
	if _, err := redisadapter.Open(valid, nil); err == nil {
		t.Fatal("expected Open to reject a missing tracer")
	}
	if _, err := redisadapter.NewTokenStore(nil); err == nil {
		t.Fatal("expected missing token store client error")
	}

	driverErr := errors.New("driver failed")
	driver := &fakeCommands{
		pingErr: driverErr, getErr: driverErr, setErr: driverErr,
		setNXErr: driverErr, deleteErr: driverErr, closeErr: driverErr,
	}
	client, err := redisadapter.New(driver, tracer)
	if err != nil {
		t.Fatalf("construct fake adapter: %v", err)
	}
	if client.Native() != nil {
		t.Fatal("wrapped fake must not expose a native client")
	}
	if err := client.Ping(ctx); !errors.Is(err, driverErr) {
		t.Fatalf("expected ping error, got %v", err)
	}
	if _, _, err := client.Get(ctx, "key"); !errors.Is(err, driverErr) {
		t.Fatalf("expected get error, got %v", err)
	}
	if err := client.Set(ctx, "key", "value", 0); !errors.Is(err, driverErr) {
		t.Fatalf("expected set error, got %v", err)
	}
	if _, err := client.SetIfAbsent(ctx, "key", "value"); !errors.Is(err, driverErr) {
		t.Fatalf("expected set-if-absent error, got %v", err)
	}
	if _, err := client.Delete(ctx, "key"); !errors.Is(err, driverErr) {
		t.Fatalf("expected delete error, got %v", err)
	}
	if err := client.Close(); !errors.Is(err, driverErr) {
		t.Fatalf("expected close error, got %v", err)
	}

	if _, _, err := client.Get(ctx, " "); err == nil {
		t.Fatal("expected blank get key error")
	}
	if err := client.Set(ctx, "", "value", 0); err == nil {
		t.Fatal("expected blank set key error")
	}
	if err := client.Set(ctx, "key", "value", -time.Second); err == nil {
		t.Fatal("expected negative set expiry error")
	}
	if _, err := client.SetIfAbsent(ctx, "", "value"); err == nil {
		t.Fatal("expected blank set-if-absent key error")
	}
	if _, err := client.Delete(ctx, "valid", " "); err == nil {
		t.Fatal("expected blank delete key error")
	}

	clockErr := errors.New("clock failed")
	system.EnqueueClockResult(readClock(t, system), clockErr)
	if _, _, err := client.Get(ctx, "key"); !errors.Is(err, clockErr) {
		t.Fatalf("expected get clock error, got %v", err)
	}
	system.EnqueueClockResult(readClock(t, system), clockErr)
	if err := client.Set(ctx, "key", "value", 0); !errors.Is(err, clockErr) {
		t.Fatalf("expected set clock error, got %v", err)
	}
	system.EnqueueClockResult(readClock(t, system), clockErr)
	if _, err := client.SetIfAbsent(ctx, "key", "value"); !errors.Is(err, clockErr) {
		t.Fatalf("expected set-if-absent clock error, got %v", err)
	}
	system.EnqueueClockResult(readClock(t, system), clockErr)
	if _, err := client.Delete(ctx, "key"); !errors.Is(err, clockErr) {
		t.Fatalf("expected delete clock error, got %v", err)
	}
	system.EnqueueClockResult(readClock(t, system), clockErr)
	if err := client.Ping(ctx); !errors.Is(err, clockErr) {
		t.Fatalf("expected clock error, got %v", err)
	}

	driver.getErr = goredis.Nil
	emitErr := errors.New("emit failed")
	emitter.EnqueueResult(emitErr)
	if _, _, err := client.Get(ctx, "missing"); !errors.Is(err, emitErr) {
		t.Fatalf("expected missing-get emit error, got %v", err)
	}
	driver.pingErr = nil
	emitter.EnqueueResult(emitErr)
	if err := client.Ping(ctx); !errors.Is(err, emitErr) {
		t.Fatalf("expected emit error, got %v", err)
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

type fakeCommands struct {
	pingErr   error
	getValue  string
	getErr    error
	setErr    error
	setNX     bool
	setNXErr  error
	deleted   int64
	deleteErr error
	closeErr  error
}

func (f *fakeCommands) Ping(context.Context) *goredis.StatusCmd {
	return goredis.NewStatusResult("PONG", f.pingErr)
}

func (f *fakeCommands) Get(context.Context, string) *goredis.StringCmd {
	return goredis.NewStringResult(f.getValue, f.getErr)
}

func (f *fakeCommands) Set(context.Context, string, any, time.Duration) *goredis.StatusCmd {
	return goredis.NewStatusResult("OK", f.setErr)
}

func (f *fakeCommands) SetNX(context.Context, string, any, time.Duration) *goredis.BoolCmd {
	return goredis.NewBoolResult(f.setNX, f.setNXErr)
}

func (f *fakeCommands) Del(context.Context, ...string) *goredis.IntCmd {
	return goredis.NewIntResult(f.deleted, f.deleteErr)
}

func (f *fakeCommands) Close() error { return f.closeErr }
