package dbinit_test

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/AtomiCloud/diene.go-consumer/lib/dbinit"
	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
	interfacestest "github.com/AtomiCloud/diene.go-interfaces/testhelper"
)

type seedRecord struct {
	id    string
	value string
}

type seedParseResult struct {
	records []seedRecord
	err     error
}

type seedParserFake struct {
	results map[string]seedParseResult
	calls   []string
}

func (f *seedParserFake) Parse(data []byte) ([]seedRecord, error) {
	content := string(data)
	f.calls = append(f.calls, content)
	result := f.results[content]
	return append([]seedRecord(nil), result.records...), result.err
}

type seedInsertResult struct {
	created bool
	err     error
}

type seedStoreFake struct {
	existing    []string
	existingErr error
	results     map[string]seedInsertResult
	calls       []seedRecord
}

func (f *seedStoreFake) ExistingSeedIDs(context.Context) ([]string, error) {
	return append([]string(nil), f.existing...), f.existingErr
}

func (f *seedStoreFake) InsertSeed(_ context.Context, record seedRecord) (bool, error) {
	f.calls = append(f.calls, record)
	result := f.results[record.id]
	return result.created, result.err
}

func seedEntry(name string) interfaces.VfsEntry {
	return interfaces.NewVfsEntry("/seed/"+name, interfaces.VfsEntryTypeFile, 1, nil)
}

func seedID(record seedRecord) string {
	return record.id
}

func newSeedLoader(
	t *testing.T,
	filesystem interfaces.Vfs,
	parser dbinit.SeedParser[seedRecord],
	store dbinit.SeedStore[seedRecord],
) *dbinit.SeedLoader[seedRecord] {
	t.Helper()
	subject, err := dbinit.NewSeedLoader(dbinit.SeedOptions[seedRecord]{
		Filesystem: filesystem,
		Parser:     parser,
		Store:      store,
		ID:         seedID,
		Directory:  "/seed",
	})
	if err != nil {
		t.Fatalf("NewSeedLoader() error = %v", err)
	}
	return subject
}

func TestSeedFilesFiltersAndSorts(t *testing.T) {
	t.Parallel()

	entries := []interfaces.VfsEntry{
		interfaces.NewVfsEntry("/seed/nested", interfaces.VfsEntryTypeDirectory, 0, nil),
		seedEntry("z-last.json"),
		seedEntry("readme.md"),
		seedEntry("a-first.json"),
	}
	files := dbinit.SeedFiles(entries)
	if len(files) != 2 || files[0].Name != "a-first.json" || files[1].Name != "z-last.json" {
		t.Fatalf("SeedFiles() = %#v", files)
	}
	if files[0].Path != "/seed/a-first.json" {
		t.Fatalf("first seed path = %q", files[0].Path)
	}
}

func TestNewSeedLoaderValidatesOptions(t *testing.T) {
	t.Parallel()

	filesystem := interfacestest.NewInMemoryVfs(interfacestest.InMemoryVfsOptions{})
	parser := &seedParserFake{results: map[string]seedParseResult{}}
	store := &seedStoreFake{results: map[string]seedInsertResult{}}
	tests := []struct {
		name    string
		options dbinit.SeedOptions[seedRecord]
		want    string
	}{
		{"filesystem", dbinit.SeedOptions[seedRecord]{Parser: parser, Store: store, ID: seedID, Directory: "/seed"}, "seed filesystem is required"},
		{"parser", dbinit.SeedOptions[seedRecord]{Filesystem: filesystem, Store: store, ID: seedID, Directory: "/seed"}, "seed parser is required"},
		{"store", dbinit.SeedOptions[seedRecord]{Filesystem: filesystem, Parser: parser, ID: seedID, Directory: "/seed"}, "seed store is required"},
		{"id", dbinit.SeedOptions[seedRecord]{Filesystem: filesystem, Parser: parser, Store: store, Directory: "/seed"}, "seed id extractor is required"},
		{"directory", dbinit.SeedOptions[seedRecord]{Filesystem: filesystem, Parser: parser, Store: store, ID: seedID, Directory: " "}, "seed directory is required"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			if _, err := dbinit.NewSeedLoader(test.options); err == nil || !strings.Contains(err.Error(), test.want) {
				t.Fatalf("NewSeedLoader() error = %v, want containing %q", err, test.want)
			}
		})
	}
}

func TestSeedLoaderInsertsOnlyMissingUniqueRecords(t *testing.T) {
	t.Parallel()

	filesystem := interfacestest.NewInMemoryVfs(interfacestest.InMemoryVfsOptions{})
	filesystem.EnqueueListResult([]interfaces.VfsEntry{
		seedEntry("z-second.json"),
		interfaces.NewVfsEntry("/seed/nested", interfaces.VfsEntryTypeDirectory, 0, nil),
		seedEntry("readme.txt"),
		seedEntry("a-first.json"),
	}, nil)
	filesystem.EnqueueReadBytesResult([]byte("first"), nil)
	filesystem.EnqueueReadBytesResult([]byte("second"), nil)
	parser := &seedParserFake{results: map[string]seedParseResult{
		"first":  {records: []seedRecord{{id: "existing", value: "old"}, {id: "new", value: "one"}, {id: "new", value: "duplicate"}}},
		"second": {records: []seedRecord{{id: "not-created", value: "two"}, {id: "not-created", value: "duplicate"}, {id: "final", value: "three"}}},
	}}
	store := &seedStoreFake{
		existing: []string{"existing"},
		results: map[string]seedInsertResult{
			"new":         {created: true},
			"not-created": {created: false},
			"final":       {created: true},
		},
	}
	subject := newSeedLoader(t, filesystem, parser, store)

	inserted, err := subject.Run(context.Background())
	if err != nil {
		t.Fatalf("Run() error = %v", err)
	}
	if inserted != 2 {
		t.Fatalf("Run() inserted = %d, want 2", inserted)
	}
	if strings.Join(parser.calls, ",") != "first,second" {
		t.Fatalf("parser calls = %#v", parser.calls)
	}
	ids := make([]string, 0, len(store.calls))
	for _, record := range store.calls {
		ids = append(ids, record.id)
	}
	if actual := strings.Join(ids, ","); actual != "new,not-created,final" {
		t.Fatalf("inserted IDs = %q", actual)
	}
}

func TestSeedLoaderReturnsEveryStageFailure(t *testing.T) {
	t.Parallel()

	want := errors.New("stage unavailable")
	t.Run("list", func(t *testing.T) {
		t.Parallel()
		filesystem := interfacestest.NewInMemoryVfs(interfacestest.InMemoryVfsOptions{})
		filesystem.EnqueueListResult(nil, want)
		subject := newSeedLoader(t, filesystem, &seedParserFake{results: map[string]seedParseResult{}}, &seedStoreFake{results: map[string]seedInsertResult{}})
		if _, err := subject.Run(context.Background()); !errors.Is(err, want) {
			t.Fatalf("Run() error = %v, want wrapping %v", err, want)
		}
	})
	t.Run("read file", func(t *testing.T) {
		t.Parallel()
		filesystem := interfacestest.NewInMemoryVfs(interfacestest.InMemoryVfsOptions{})
		filesystem.EnqueueListResult([]interfaces.VfsEntry{seedEntry("one.json")}, nil)
		filesystem.EnqueueReadBytesResult(nil, want)
		subject := newSeedLoader(t, filesystem, &seedParserFake{results: map[string]seedParseResult{}}, &seedStoreFake{results: map[string]seedInsertResult{}})
		if _, err := subject.Run(context.Background()); !errors.Is(err, want) {
			t.Fatalf("Run() error = %v, want wrapping %v", err, want)
		}
	})
	t.Run("parse file", func(t *testing.T) {
		t.Parallel()
		filesystem := interfacestest.NewInMemoryVfs(interfacestest.InMemoryVfsOptions{})
		filesystem.EnqueueListResult([]interfaces.VfsEntry{seedEntry("one.json")}, nil)
		filesystem.EnqueueReadBytesResult([]byte("bad"), nil)
		parser := &seedParserFake{results: map[string]seedParseResult{"bad": {err: want}}}
		subject := newSeedLoader(t, filesystem, parser, &seedStoreFake{results: map[string]seedInsertResult{}})
		if _, err := subject.Run(context.Background()); !errors.Is(err, want) {
			t.Fatalf("Run() error = %v, want wrapping %v", err, want)
		}
	})
	t.Run("existing IDs", func(t *testing.T) {
		t.Parallel()
		filesystem := interfacestest.NewInMemoryVfs(interfacestest.InMemoryVfsOptions{})
		filesystem.EnqueueListResult(nil, nil)
		subject := newSeedLoader(t, filesystem, &seedParserFake{results: map[string]seedParseResult{}}, &seedStoreFake{existingErr: want, results: map[string]seedInsertResult{}})
		if _, err := subject.Run(context.Background()); !errors.Is(err, want) {
			t.Fatalf("Run() error = %v, want wrapping %v", err, want)
		}
	})
	t.Run("blank ID", func(t *testing.T) {
		t.Parallel()
		filesystem := interfacestest.NewInMemoryVfs(interfacestest.InMemoryVfsOptions{})
		filesystem.EnqueueListResult([]interfaces.VfsEntry{seedEntry("one.json")}, nil)
		filesystem.EnqueueReadBytesResult([]byte("blank"), nil)
		parser := &seedParserFake{results: map[string]seedParseResult{"blank": {records: []seedRecord{{id: " ", value: "bad"}}}}}
		subject := newSeedLoader(t, filesystem, parser, &seedStoreFake{results: map[string]seedInsertResult{}})
		if inserted, err := subject.Run(context.Background()); inserted != 0 || err == nil || !strings.Contains(err.Error(), "seed record id is required") {
			t.Fatalf("Run() = (%d, %v)", inserted, err)
		}
	})
	t.Run("insert", func(t *testing.T) {
		t.Parallel()
		filesystem := interfacestest.NewInMemoryVfs(interfacestest.InMemoryVfsOptions{})
		filesystem.EnqueueListResult([]interfaces.VfsEntry{seedEntry("one.json")}, nil)
		filesystem.EnqueueReadBytesResult([]byte("record"), nil)
		parser := &seedParserFake{results: map[string]seedParseResult{"record": {records: []seedRecord{{id: "one", value: "value"}}}}}
		store := &seedStoreFake{results: map[string]seedInsertResult{"one": {err: want}}}
		subject := newSeedLoader(t, filesystem, parser, store)
		if inserted, err := subject.Run(context.Background()); inserted != 0 || !errors.Is(err, want) {
			t.Fatalf("Run() = (%d, %v), want (0, wrapping %v)", inserted, err, want)
		}
	})
}

type runnerFake struct {
	name  string
	calls *[]string
	err   error
}

func (f *runnerFake) Run(context.Context) error {
	*f.calls = append(*f.calls, f.name)
	return f.err
}

type seederFake struct {
	name   string
	calls  *[]string
	seeded int
	err    error
}

func (f *seederFake) Run(context.Context) (int, error) {
	*f.calls = append(*f.calls, f.name)
	return f.seeded, f.err
}

func initializerOptions(calls *[]string) dbinit.InitializerOptions {
	return dbinit.InitializerOptions{
		Reachability: &runnerFake{name: "reachability", calls: calls},
		Buckets:      &runnerFake{name: "buckets", calls: calls},
		Migrations:   &runnerFake{name: "migrations", calls: calls},
		Seeds:        &seederFake{name: "seeds", calls: calls, seeded: 3},
	}
}

func TestNewInitializerValidatesEveryPhase(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name   string
		change func(*dbinit.InitializerOptions)
		want   string
	}{
		{"reachability", func(options *dbinit.InitializerOptions) { options.Reachability = nil }, "reachability phase is required"},
		{"buckets", func(options *dbinit.InitializerOptions) { options.Buckets = nil }, "bucket phase is required"},
		{"migrations", func(options *dbinit.InitializerOptions) { options.Migrations = nil }, "migration phase is required"},
		{"seeds", func(options *dbinit.InitializerOptions) { options.Seeds = nil }, "seed phase is required"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			calls := []string{}
			options := initializerOptions(&calls)
			test.change(&options)
			if _, err := dbinit.NewInitializer(options); err == nil || !strings.Contains(err.Error(), test.want) {
				t.Fatalf("NewInitializer() error = %v, want containing %q", err, test.want)
			}
		})
	}
}

func TestInitializerRunsEveryPhaseInOrder(t *testing.T) {
	t.Parallel()

	calls := []string{}
	subject, err := dbinit.NewInitializer(initializerOptions(&calls))
	if err != nil {
		t.Fatalf("NewInitializer() error = %v", err)
	}
	actual, err := subject.Run(context.Background())
	if err != nil {
		t.Fatalf("Run() error = %v", err)
	}
	if actual.Seeded != 3 || strings.Join(calls, ",") != "reachability,buckets,migrations,seeds" {
		t.Fatalf("Run() = %#v, calls = %#v", actual, calls)
	}
}

func TestInitializerStopsAtEveryFailedPhase(t *testing.T) {
	t.Parallel()

	want := errors.New("phase unavailable")
	tests := []struct {
		name      string
		configure func(*dbinit.InitializerOptions)
		wantCalls string
	}{
		{"reachability", func(options *dbinit.InitializerOptions) { options.Reachability.(*runnerFake).err = want }, "reachability"},
		{"buckets", func(options *dbinit.InitializerOptions) { options.Buckets.(*runnerFake).err = want }, "reachability,buckets"},
		{"migrations", func(options *dbinit.InitializerOptions) { options.Migrations.(*runnerFake).err = want }, "reachability,buckets,migrations"},
		{"seeds", func(options *dbinit.InitializerOptions) { options.Seeds.(*seederFake).err = want }, "reachability,buckets,migrations,seeds"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			calls := []string{}
			options := initializerOptions(&calls)
			test.configure(&options)
			subject, err := dbinit.NewInitializer(options)
			if err != nil {
				t.Fatalf("NewInitializer() error = %v", err)
			}
			actual, runErr := subject.Run(context.Background())
			if actual != (dbinit.Result{}) || !errors.Is(runErr, want) {
				t.Fatalf("Run() = (%#v, %v), want zero result and wrapping %v", actual, runErr, want)
			}
			if joined := strings.Join(calls, ","); joined != test.wantCalls {
				t.Fatalf("phase calls = %q, want %q", joined, test.wantCalls)
			}
		})
	}
}
