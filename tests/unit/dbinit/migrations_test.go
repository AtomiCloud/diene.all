package dbinit_test

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-consumer/lib/dbinit"
	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
	interfacestest "github.com/AtomiCloud/diene.go-interfaces/testhelper"
)

type migrationCall struct {
	name      string
	statement string
}

type migrationStoreFake struct {
	prepareErr   error
	appliedNames []string
	appliedErr   error
	applyErrors  map[string]error
	prepareCalls int
	applyCalls   []migrationCall
}

func (f *migrationStoreFake) PrepareMigrations(context.Context) error {
	f.prepareCalls++
	return f.prepareErr
}

func (f *migrationStoreFake) AppliedMigrations(context.Context) ([]string, error) {
	return append([]string(nil), f.appliedNames...), f.appliedErr
}

func (f *migrationStoreFake) ApplyMigration(_ context.Context, name string, statement string) error {
	f.applyCalls = append(f.applyCalls, migrationCall{name: name, statement: statement})
	return f.applyErrors[name]
}

type markerStoreFake struct {
	created bool
	err     error
	keys    []string
	values  []string
}

func (f *markerStoreFake) SetIfAbsent(_ context.Context, key string, value string) (bool, error) {
	f.keys = append(f.keys, key)
	f.values = append(f.values, value)
	return f.created, f.err
}

func migrationEntry(name string) interfaces.VfsEntry {
	return interfaces.NewVfsEntry("/migrations/"+name, interfaces.VfsEntryTypeFile, 1, nil)
}

func newMigrationRunner(
	t *testing.T,
	filesystem interfaces.Vfs,
	postgres dbinit.MigrationStore,
	redis dbinit.MarkerStore,
) *dbinit.MigrationRunner {
	t.Helper()
	subject, err := dbinit.NewMigrationRunner(dbinit.MigrationOptions{
		Filesystem: filesystem,
		Postgres:   postgres,
		Redis:      redis,
		Directory:  "/migrations",
		MarkerKey:  "migrations:ready",
	})
	if err != nil {
		t.Fatalf("NewMigrationRunner() error = %v", err)
	}
	return subject
}

func TestValidMigrationName(t *testing.T) {
	t.Parallel()

	tests := map[string]bool{
		"001_init.sql":       true,
		"42-add-index.sql":   true,
		"1_a1-b2.sql":        true,
		"001_init.txt":       false,
		"_init.sql":          false,
		"001.sql":            false,
		"001_.sql":           false,
		"001_Init.sql":       false,
		"001_has.dot.sql":    false,
		"migration_init.sql": false,
	}
	for name, want := range tests {
		if actual := dbinit.ValidMigrationName(name); actual != want {
			t.Fatalf("ValidMigrationName(%q) = %t, want %t", name, actual, want)
		}
	}
}

func TestMigrationFilesFiltersValidatesAndSorts(t *testing.T) {
	t.Parallel()

	modified := time.Date(2026, time.July, 26, 22, 0, 0, 0, time.UTC)
	entries := []interfaces.VfsEntry{
		interfaces.NewVfsEntry("/migrations/subdir", interfaces.VfsEntryTypeDirectory, 0, &modified),
		interfaces.NewVfsEntry("/migrations/readme.txt", interfaces.VfsEntryTypeFile, 1, nil),
		migrationEntry("010_second.sql"),
		migrationEntry("002_first.sql"),
	}
	files, err := dbinit.MigrationFiles(entries)
	if err != nil {
		t.Fatalf("MigrationFiles() error = %v", err)
	}
	if len(files) != 2 || files[0].Name != "002_first.sql" || files[1].Name != "010_second.sql" {
		t.Fatalf("MigrationFiles() = %#v", files)
	}
	if files[0].Path != "/migrations/002_first.sql" {
		t.Fatalf("first migration path = %q", files[0].Path)
	}

	if _, err := dbinit.MigrationFiles([]interfaces.VfsEntry{migrationEntry("001_Bad.sql")}); err == nil || !strings.Contains(err.Error(), "invalid migration name") {
		t.Fatalf("MigrationFiles() invalid-name error = %v", err)
	}
}

func TestNewMigrationRunnerValidatesOptions(t *testing.T) {
	t.Parallel()

	filesystem := interfacestest.NewInMemoryVfs(interfacestest.InMemoryVfsOptions{})
	postgres := &migrationStoreFake{applyErrors: map[string]error{}}
	redis := &markerStoreFake{}
	tests := []struct {
		name    string
		options dbinit.MigrationOptions
		want    string
	}{
		{"filesystem", dbinit.MigrationOptions{Postgres: postgres, Redis: redis, Directory: "/migrations", MarkerKey: "key"}, "migration filesystem is required"},
		{"postgres", dbinit.MigrationOptions{Filesystem: filesystem, Redis: redis, Directory: "/migrations", MarkerKey: "key"}, "migration postgres store is required"},
		{"redis", dbinit.MigrationOptions{Filesystem: filesystem, Postgres: postgres, Directory: "/migrations", MarkerKey: "key"}, "migration marker store is required"},
		{"directory", dbinit.MigrationOptions{Filesystem: filesystem, Postgres: postgres, Redis: redis, Directory: " ", MarkerKey: "key"}, "migration directory is required"},
		{"marker key", dbinit.MigrationOptions{Filesystem: filesystem, Postgres: postgres, Redis: redis, Directory: "/migrations", MarkerKey: ""}, "redis migration key is required"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			if _, err := dbinit.NewMigrationRunner(test.options); err == nil || !strings.Contains(err.Error(), test.want) {
				t.Fatalf("NewMigrationRunner() error = %v, want containing %q", err, test.want)
			}
		})
	}
}

func TestMigrationRunnerAppliesMissingFilesInOrderAndMarksRedis(t *testing.T) {
	t.Parallel()

	filesystem := interfacestest.NewInMemoryVfs(interfacestest.InMemoryVfsOptions{})
	filesystem.EnqueueListResult([]interfaces.VfsEntry{
		migrationEntry("003_third.sql"),
		interfaces.NewVfsEntry("/migrations/nested", interfaces.VfsEntryTypeDirectory, 0, nil),
		migrationEntry("001_first.sql"),
		interfaces.NewVfsEntry("/migrations/readme.md", interfaces.VfsEntryTypeFile, 1, nil),
		migrationEntry("002_second.sql"),
	}, nil)
	filesystem.EnqueueReadTextResult("CREATE TABLE first (id TEXT)", nil)
	filesystem.EnqueueReadTextResult("CREATE TABLE third (id TEXT)", nil)
	postgres := &migrationStoreFake{appliedNames: []string{"002_second.sql"}, applyErrors: map[string]error{}}
	redis := &markerStoreFake{created: false}
	subject := newMigrationRunner(t, filesystem, postgres, redis)

	if err := subject.Run(context.Background()); err != nil {
		t.Fatalf("Run() error = %v", err)
	}
	if postgres.prepareCalls != 1 || len(postgres.applyCalls) != 2 {
		t.Fatalf("migration calls = prepare %d, apply %#v", postgres.prepareCalls, postgres.applyCalls)
	}
	if postgres.applyCalls[0].name != "001_first.sql" || postgres.applyCalls[1].name != "003_third.sql" {
		t.Fatalf("migration order = %#v", postgres.applyCalls)
	}
	if postgres.applyCalls[0].statement != "CREATE TABLE first (id TEXT)" || postgres.applyCalls[1].statement != "CREATE TABLE third (id TEXT)" {
		t.Fatalf("migration statements = %#v", postgres.applyCalls)
	}
	if strings.Join(redis.keys, ",") != "migrations:ready" || strings.Join(redis.values, ",") != "ready" {
		t.Fatalf("marker calls = keys %#v, values %#v", redis.keys, redis.values)
	}
}

func TestMigrationRunnerReturnsEveryStageFailure(t *testing.T) {
	t.Parallel()

	want := errors.New("stage unavailable")
	t.Run("prepare", func(t *testing.T) {
		t.Parallel()
		filesystem := interfacestest.NewInMemoryVfs(interfacestest.InMemoryVfsOptions{})
		subject := newMigrationRunner(t, filesystem, &migrationStoreFake{prepareErr: want, applyErrors: map[string]error{}}, &markerStoreFake{})
		if err := subject.Run(context.Background()); !errors.Is(err, want) {
			t.Fatalf("Run() error = %v, want wrapping %v", err, want)
		}
	})
	t.Run("read ledger", func(t *testing.T) {
		t.Parallel()
		filesystem := interfacestest.NewInMemoryVfs(interfacestest.InMemoryVfsOptions{})
		subject := newMigrationRunner(t, filesystem, &migrationStoreFake{appliedErr: want, applyErrors: map[string]error{}}, &markerStoreFake{})
		if err := subject.Run(context.Background()); !errors.Is(err, want) {
			t.Fatalf("Run() error = %v, want wrapping %v", err, want)
		}
	})
	t.Run("list", func(t *testing.T) {
		t.Parallel()
		filesystem := interfacestest.NewInMemoryVfs(interfacestest.InMemoryVfsOptions{})
		filesystem.EnqueueListResult(nil, want)
		subject := newMigrationRunner(t, filesystem, &migrationStoreFake{applyErrors: map[string]error{}}, &markerStoreFake{})
		if err := subject.Run(context.Background()); !errors.Is(err, want) {
			t.Fatalf("Run() error = %v, want wrapping %v", err, want)
		}
	})
	t.Run("invalid filename", func(t *testing.T) {
		t.Parallel()
		filesystem := interfacestest.NewInMemoryVfs(interfacestest.InMemoryVfsOptions{})
		filesystem.EnqueueListResult([]interfaces.VfsEntry{migrationEntry("001_Bad.sql")}, nil)
		subject := newMigrationRunner(t, filesystem, &migrationStoreFake{applyErrors: map[string]error{}}, &markerStoreFake{})
		if err := subject.Run(context.Background()); err == nil || !strings.Contains(err.Error(), "invalid migration name") {
			t.Fatalf("Run() error = %v", err)
		}
	})
	t.Run("read file", func(t *testing.T) {
		t.Parallel()
		filesystem := interfacestest.NewInMemoryVfs(interfacestest.InMemoryVfsOptions{})
		filesystem.EnqueueListResult([]interfaces.VfsEntry{migrationEntry("001_init.sql")}, nil)
		filesystem.EnqueueReadTextResult("", want)
		subject := newMigrationRunner(t, filesystem, &migrationStoreFake{applyErrors: map[string]error{}}, &markerStoreFake{})
		if err := subject.Run(context.Background()); !errors.Is(err, want) {
			t.Fatalf("Run() error = %v, want wrapping %v", err, want)
		}
	})
	t.Run("empty file", func(t *testing.T) {
		t.Parallel()
		filesystem := interfacestest.NewInMemoryVfs(interfacestest.InMemoryVfsOptions{})
		filesystem.EnqueueListResult([]interfaces.VfsEntry{migrationEntry("001_init.sql")}, nil)
		filesystem.EnqueueReadTextResult(" \n", nil)
		subject := newMigrationRunner(t, filesystem, &migrationStoreFake{applyErrors: map[string]error{}}, &markerStoreFake{})
		if err := subject.Run(context.Background()); err == nil || !strings.Contains(err.Error(), "migration \"001_init.sql\" is empty") {
			t.Fatalf("Run() error = %v", err)
		}
	})
	t.Run("apply", func(t *testing.T) {
		t.Parallel()
		filesystem := interfacestest.NewInMemoryVfs(interfacestest.InMemoryVfsOptions{})
		filesystem.EnqueueListResult([]interfaces.VfsEntry{migrationEntry("001_init.sql")}, nil)
		filesystem.EnqueueReadTextResult("SELECT 1", nil)
		postgres := &migrationStoreFake{applyErrors: map[string]error{"001_init.sql": want}}
		subject := newMigrationRunner(t, filesystem, postgres, &markerStoreFake{})
		if err := subject.Run(context.Background()); !errors.Is(err, want) {
			t.Fatalf("Run() error = %v, want wrapping %v", err, want)
		}
	})
	t.Run("redis marker", func(t *testing.T) {
		t.Parallel()
		filesystem := interfacestest.NewInMemoryVfs(interfacestest.InMemoryVfsOptions{})
		filesystem.EnqueueListResult(nil, nil)
		subject := newMigrationRunner(t, filesystem, &migrationStoreFake{applyErrors: map[string]error{}}, &markerStoreFake{err: want})
		if err := subject.Run(context.Background()); !errors.Is(err, want) {
			t.Fatalf("Run() error = %v, want wrapping %v", err, want)
		}
	})
}
