package postgres_test

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	postgresadapter "github.com/AtomiCloud/diene.go-consumer/adapters/postgres"
	"github.com/AtomiCloud/diene.go-consumer/adapters/tracing"
	"github.com/AtomiCloud/diene.go-consumer/lib/domain"
	"github.com/AtomiCloud/diene.go-consumer/lib/seedrecord"
	interfaceshelper "github.com/AtomiCloud/diene.go-interfaces/testhelper"
	otelhelper "github.com/AtomiCloud/diene.go-otel/testhelper"
	"github.com/AtomiCloud/diene.go-standard-config/lib/standardconfig"
	standardhelper "github.com/AtomiCloud/diene.go-standard-config/testhelper"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

func TestPoolAgainstPostgres(t *testing.T) {
	ctx := context.Background()
	started, startErr := standardhelper.StartPostgres(ctx, standardhelper.PostgresOptions{})
	if startErr != nil {
		t.Fatalf("start Postgres: %v", startErr)
	}
	t.Cleanup(func() {
		if terminateErr := started.Terminate(ctx); terminateErr != nil {
			t.Errorf("terminate Postgres: %v", terminateErr)
		}
	})

	tracer, emitter, _ := newTracer(t)
	pool, openErr := postgresadapter.Open(ctx, started.Entry, tracer)
	if openErr != nil {
		t.Fatalf("open adapter: %v", openErr)
	}
	t.Cleanup(func() {
		if closeErr := pool.Close(); closeErr != nil {
			t.Errorf("close adapter: %v", closeErr)
		}
	})

	if err := pool.Ping(ctx); err != nil {
		t.Fatalf("ping: %v", err)
	}
	if err := pool.PrepareMigrations(ctx); err != nil {
		t.Fatalf("prepare migrations: %v", err)
	}
	applied, listErr := pool.AppliedMigrations(ctx)
	if listErr != nil {
		t.Fatalf("list empty migrations: %v", listErr)
	}
	if len(applied) != 0 {
		t.Fatalf("expected no migrations, got %v", applied)
	}
	if err := pool.ApplyMigration(ctx, "001_create_items", "CREATE TABLE items (id TEXT PRIMARY KEY)"); err != nil {
		t.Fatalf("apply migration: %v", err)
	}
	applied, listErr = pool.AppliedMigrations(ctx)
	if listErr != nil {
		t.Fatalf("list migrations: %v", listErr)
	}
	if len(applied) != 1 || applied[0] != "001_create_items" {
		t.Fatalf("unexpected migrations: %v", applied)
	}
	affected, execErr := pool.Exec(ctx, "INSERT INTO items (id) VALUES ($1)", "one")
	if execErr != nil || affected != 1 {
		t.Fatalf("insert item: affected=%d err=%v", affected, execErr)
	}
	count, queryErr := pool.QueryInt64(ctx, "SELECT COUNT(*) FROM items")
	if queryErr != nil || count != 1 {
		t.Fatalf("count items: count=%d err=%v", count, queryErr)
	}
	if _, err := pool.Exec(ctx, `CREATE TABLE processed_messages (
id TEXT PRIMARY KEY, object_key TEXT NOT NULL, payload TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL
)`); err != nil {
		t.Fatalf("create processed-message table: %v", err)
	}
	if _, err := pool.Exec(ctx, "CREATE TABLE seed_records (id TEXT PRIMARY KEY, value TEXT NOT NULL)"); err != nil {
		t.Fatalf("create seed table: %v", err)
	}
	record := domain.ProcessedMessageRecord{
		ID: "message-one", ObjectKey: "messages/one", Payload: "payload", CreatedAt: time.Now().UTC(),
	}
	inserted, insertErr := pool.Insert(ctx, record)
	if insertErr != nil || !inserted {
		t.Fatalf("insert processed message: inserted=%t err=%v", inserted, insertErr)
	}
	inserted, insertErr = pool.Insert(ctx, record)
	if insertErr != nil || inserted {
		t.Fatalf("repeat processed message: inserted=%t err=%v", inserted, insertErr)
	}
	if existing, err := pool.ExistingSeedIDs(ctx); err != nil || len(existing) != 0 {
		t.Fatalf("list empty seeds: seeds=%v err=%v", existing, err)
	}
	seeded, seedErr := pool.InsertSeed(ctx, seedrecord.Record{ID: "seed-one", Value: "value"})
	if seedErr != nil || !seeded {
		t.Fatalf("insert seed: inserted=%t err=%v", seeded, seedErr)
	}
	seeded, seedErr = pool.InsertSeed(ctx, seedrecord.Record{ID: "seed-one", Value: "value"})
	if seedErr != nil || seeded {
		t.Fatalf("repeat seed: inserted=%t err=%v", seeded, seedErr)
	}
	if existing, err := pool.ExistingSeedIDs(ctx); err != nil || len(existing) != 1 || existing[0] != "seed-one" {
		t.Fatalf("list seeds: seeds=%v err=%v", existing, err)
	}
	if len(emitter.Records()) < 14 {
		t.Fatalf("expected adapter traces, got %d", len(emitter.Records()))
	}
}

func TestPoolConstructionFailures(t *testing.T) {
	t.Parallel()
	ctx := context.Background()
	tracer, _, _ := newTracer(t)
	valid := validEntry()

	tests := []struct {
		name   string
		mutate func(*standardconfig.PostgresEntry)
	}{
		{"host", func(entry *standardconfig.PostgresEntry) { entry.Host = "" }},
		{"low port", func(entry *standardconfig.PostgresEntry) { entry.Port = 0 }},
		{"high port", func(entry *standardconfig.PostgresEntry) { entry.Port = 65536 }},
		{"database", func(entry *standardconfig.PostgresEntry) { entry.Database = "" }},
		{"username", func(entry *standardconfig.PostgresEntry) { entry.Username = "" }},
		{"negative pool minimum", func(entry *standardconfig.PostgresEntry) { entry.Pool.Min = -1 }},
		{"zero pool maximum", func(entry *standardconfig.PostgresEntry) { entry.Pool.Max = 0 }},
		{"inverted pool", func(entry *standardconfig.PostgresEntry) { entry.Pool.Min = 3; entry.Pool.Max = 2 }},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			entry := valid
			test.mutate(&entry)
			if _, err := postgresadapter.OpenWithFactory(ctx, entry, tracer, func(context.Context, string) (postgresadapter.PoolAPI, error) {
				t.Fatal("factory must not run for invalid config")
				return nil, nil
			}); err == nil {
				t.Fatal("expected validation error")
			}
		})
	}

	if _, err := postgresadapter.OpenWithFactory(ctx, valid, tracer, nil); err == nil {
		t.Fatal("expected missing factory error")
	}
	factoryErr := errors.New("factory failed")
	if _, err := postgresadapter.OpenWithFactory(ctx, valid, tracer, func(context.Context, string) (postgresadapter.PoolAPI, error) {
		return nil, factoryErr
	}); !errors.Is(err, factoryErr) {
		t.Fatalf("expected factory error, got %v", err)
	}
	driver := &fakePool{}
	if _, err := postgresadapter.OpenWithFactory(ctx, valid, nil, func(_ context.Context, connectionString string) (postgresadapter.PoolAPI, error) {
		if !strings.Contains(connectionString, "sslmode=require") || !strings.Contains(connectionString, "pool_min_conns=1") {
			t.Fatalf("unexpected connection string: %s", connectionString)
		}
		return driver, nil
	}); err == nil || !driver.closed {
		t.Fatalf("expected tracer error and closed driver: err=%v closed=%t", err, driver.closed)
	}

	if _, err := postgresadapter.New(nil, tracer); err == nil {
		t.Fatal("expected missing pool error")
	}
	if _, err := postgresadapter.New(&fakePool{}, nil); err == nil {
		t.Fatal("expected missing tracer error")
	}
}

func TestPoolOperationFailures(t *testing.T) {
	t.Parallel()
	ctx := context.Background()
	tracer, emitter, system := newTracer(t)
	driverErr := errors.New("driver failed")
	driver := &fakePool{
		pingErr: driverErr,
		execErr: driverErr,
		row:     fakeRow{err: driverErr},
		rows:    &fakeRows{},
	}
	pool, err := postgresadapter.New(driver, tracer)
	if err != nil {
		t.Fatalf("construct adapter: %v", err)
	}
	if err := pool.Ping(ctx); !errors.Is(err, driverErr) {
		t.Fatalf("expected ping error, got %v", err)
	}
	if _, err := pool.Exec(ctx, ""); err == nil {
		t.Fatal("expected blank statement error")
	}
	if _, err := pool.Exec(ctx, "SELECT broken"); !errors.Is(err, driverErr) {
		t.Fatalf("expected exec error, got %v", err)
	}
	if _, err := pool.QueryInt64(ctx, ""); err == nil {
		t.Fatal("expected blank query error")
	}
	if _, err := pool.QueryInt64(ctx, "SELECT broken"); !errors.Is(err, driverErr) {
		t.Fatalf("expected scan error, got %v", err)
	}
	if _, err := pool.Insert(ctx, domain.ProcessedMessageRecord{}); err == nil {
		t.Fatal("expected blank processed-message id error")
	}
	if _, err := pool.Insert(ctx, domain.ProcessedMessageRecord{ID: "id"}); !errors.Is(err, driverErr) {
		t.Fatalf("expected processed-message insert error, got %v", err)
	}
	if _, err := pool.InsertSeed(ctx, seedrecord.Record{}); err == nil {
		t.Fatal("expected blank seed id error")
	}
	if _, err := pool.InsertSeed(ctx, seedrecord.Record{ID: "id"}); !errors.Is(err, driverErr) {
		t.Fatalf("expected seed insert error, got %v", err)
	}

	clockErr := errors.New("clock failed")
	system.EnqueueClockResult(timeNow(t, system), clockErr)
	if err := pool.Ping(ctx); !errors.Is(err, clockErr) {
		t.Fatalf("expected ping clock error, got %v", err)
	}
	system.EnqueueClockResult(timeNow(t, system), clockErr)
	if _, err := pool.Exec(ctx, "SELECT 1"); !errors.Is(err, clockErr) {
		t.Fatalf("expected exec clock error, got %v", err)
	}
	system.EnqueueClockResult(timeNow(t, system), clockErr)
	if _, err := pool.QueryInt64(ctx, "SELECT 1"); !errors.Is(err, clockErr) {
		t.Fatalf("expected query clock error, got %v", err)
	}

	driver.execErr = nil
	driver.execTag = pgconn.NewCommandTag("UPDATE 2")
	emitErr := errors.New("emit failed")
	emitter.EnqueueResult(emitErr)
	if _, err := pool.Exec(ctx, "UPDATE items"); !errors.Is(err, emitErr) {
		t.Fatalf("expected exec emit error, got %v", err)
	}
}

func TestMigrationFailurePaths(t *testing.T) {
	t.Parallel()
	ctx := context.Background()
	tracer, emitter, system := newTracer(t)
	driverErr := errors.New("query failed")
	driver := &fakePool{queryErr: driverErr}
	pool, err := postgresadapter.New(driver, tracer)
	if err != nil {
		t.Fatalf("construct adapter: %v", err)
	}
	if _, err := pool.AppliedMigrations(ctx); !errors.Is(err, driverErr) {
		t.Fatalf("expected query error, got %v", err)
	}

	scanErr := errors.New("scan failed")
	driver.queryErr = nil
	driver.rows = &fakeRows{values: []string{"one"}, scanErr: scanErr}
	if _, err := pool.AppliedMigrations(ctx); !errors.Is(err, scanErr) {
		t.Fatalf("expected scan error, got %v", err)
	}
	rowsErr := errors.New("rows failed")
	driver.rows = &fakeRows{rowsErr: rowsErr}
	if _, err := pool.AppliedMigrations(ctx); !errors.Is(err, rowsErr) {
		t.Fatalf("expected rows error, got %v", err)
	}

	driver.rows = &fakeRows{values: []string{"one", "two"}}
	emitErr := errors.New("emit failed")
	emitter.EnqueueResult(emitErr)
	if _, err := pool.AppliedMigrations(ctx); !errors.Is(err, emitErr) {
		t.Fatalf("expected emit error, got %v", err)
	}
	clockErr := errors.New("clock failed")
	system.EnqueueClockResult(timeNow(t, system), clockErr)
	if _, err := pool.AppliedMigrations(ctx); !errors.Is(err, clockErr) {
		t.Fatalf("expected clock error, got %v", err)
	}

	if err := pool.ApplyMigration(ctx, "bad/name", "SELECT 1"); err == nil {
		t.Fatal("expected invalid migration name error")
	}
	if err := pool.ApplyMigration(ctx, "", "SELECT 1"); err == nil {
		t.Fatal("expected blank migration name error")
	}
	if err := pool.ApplyMigration(ctx, "valid-name", " "); err == nil {
		t.Fatal("expected blank migration statement error")
	}
	driver.execErr = nil
	if err := pool.ApplyMigration(ctx, "A1._-", "SELECT 1"); err != nil {
		t.Fatalf("expected all valid migration-name characters: %v", err)
	}
}

func validEntry() standardconfig.PostgresEntry {
	return standardconfig.PostgresEntry{
		Host: "db.invalid", Port: 5432, Database: "app", Username: "app", Password: "secret",
		SSL: true, Pool: standardconfig.PoolSizing{Min: 1, Max: 3},
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

func timeNow(t *testing.T, system *interfaceshelper.InMemorySystem) time.Time {
	t.Helper()
	now, err := system.NowUTC()
	if err != nil {
		t.Fatalf("read clock: %v", err)
	}
	return now
}

type fakePool struct {
	pingErr  error
	execTag  pgconn.CommandTag
	execErr  error
	row      pgx.Row
	rows     pgx.Rows
	queryErr error
	closed   bool
}

func (f *fakePool) Ping(context.Context) error { return f.pingErr }

func (f *fakePool) Exec(context.Context, string, ...any) (pgconn.CommandTag, error) {
	return f.execTag, f.execErr
}

func (f *fakePool) Query(context.Context, string, ...any) (pgx.Rows, error) {
	return f.rows, f.queryErr
}

func (f *fakePool) QueryRow(context.Context, string, ...any) pgx.Row { return f.row }

func (f *fakePool) Close() { f.closed = true }

type fakeRow struct {
	value int64
	err   error
}

func (f fakeRow) Scan(destinations ...any) error {
	if f.err != nil {
		return f.err
	}
	value, ok := destinations[0].(*int64)
	if !ok {
		return errors.New("fake row: expected *int64")
	}
	*value = f.value
	return nil
}

type fakeRows struct {
	values  []string
	index   int
	scanErr error
	rowsErr error
	closed  bool
}

func (f *fakeRows) Close()                                     { f.closed = true }
func (f *fakeRows) Err() error                                 { return f.rowsErr }
func (*fakeRows) CommandTag() pgconn.CommandTag                { return pgconn.CommandTag{} }
func (*fakeRows) FieldDescriptions() []pgconn.FieldDescription { return nil }
func (f *fakeRows) Next() bool {
	if f.index >= len(f.values) {
		return false
	}
	f.index++
	return true
}

func (f *fakeRows) Scan(destinations ...any) error {
	if f.scanErr != nil {
		return f.scanErr
	}
	value, ok := destinations[0].(*string)
	if !ok {
		return errors.New("fake rows: expected *string")
	}
	*value = f.values[f.index-1]
	return nil
}
func (*fakeRows) Values() ([]any, error) { return nil, nil }
func (*fakeRows) RawValues() [][]byte    { return nil }
func (*fakeRows) Conn() *pgx.Conn        { return nil }
