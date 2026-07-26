package dbinit

import (
	"context"
	"errors"
	"fmt"
	"path"
	"slices"
	"strings"

	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
)

// SeedParser parses one seed file into domain records.
type SeedParser[Record any] interface {
	Parse(data []byte) ([]Record, error)
}

// SeedStore persists seed records idempotently.
type SeedStore[Record any] interface {
	ExistingSeedIDs(ctx context.Context) ([]string, error)
	InsertSeed(ctx context.Context, record Record) (bool, error)
}

// IDOf extracts the stable identity of one seed record.
type IDOf[Record any] func(record Record) string

// SeedFile is one JSON seed file found through the VFS seam.
type SeedFile struct {
	Name string
	Path string
}

// SeedFiles filters and sorts direct JSON file entries.
func SeedFiles(entries []interfaces.VfsEntry) []SeedFile {
	files := make([]SeedFile, 0, len(entries))
	for _, entry := range entries {
		if entry.Type != interfaces.VfsEntryTypeFile {
			continue
		}
		name := path.Base(entry.Path)
		if !strings.HasSuffix(name, ".json") {
			continue
		}
		files = append(files, SeedFile{Name: name, Path: entry.Path})
	}
	slices.SortFunc(files, func(left, right SeedFile) int { return strings.Compare(left.Name, right.Name) })
	return files
}

// SeedOptions configures a SeedLoader.
type SeedOptions[Record any] struct {
	Filesystem interfaces.Vfs
	Parser     SeedParser[Record]
	Store      SeedStore[Record]
	ID         IDOf[Record]
	Directory  string
}

// SeedLoader loads JSON seed files and inserts records that do not exist.
type SeedLoader[Record any] struct {
	filesystem interfaces.Vfs
	parser     SeedParser[Record]
	store      SeedStore[Record]
	id         IDOf[Record]
	directory  string
}

// NewSeedLoader creates an injected idempotent seed loader.
func NewSeedLoader[Record any](options SeedOptions[Record]) (*SeedLoader[Record], error) {
	if options.Filesystem == nil {
		return nil, errors.New("dbinit: seed filesystem is required")
	}
	if options.Parser == nil {
		return nil, errors.New("dbinit: seed parser is required")
	}
	if options.Store == nil {
		return nil, errors.New("dbinit: seed store is required")
	}
	if options.ID == nil {
		return nil, errors.New("dbinit: seed id extractor is required")
	}
	if strings.TrimSpace(options.Directory) == "" {
		return nil, errors.New("dbinit: seed directory is required")
	}
	return &SeedLoader[Record]{
		filesystem: options.Filesystem,
		parser:     options.Parser,
		store:      options.Store,
		id:         options.ID,
		directory:  options.Directory,
	}, nil
}

// Run inserts only seed records whose IDs are not already present.
func (s *SeedLoader[Record]) Run(ctx context.Context) (int, error) {
	entries, err := s.filesystem.List(ctx, s.directory, interfaces.ListOptions{})
	if err != nil {
		return 0, fmt.Errorf("dbinit: list seed files: %w", err)
	}
	records := make([]Record, 0)
	for _, file := range SeedFiles(entries) {
		data, readErr := s.filesystem.ReadBytes(ctx, file.Path)
		if readErr != nil {
			return 0, fmt.Errorf("dbinit: read seed file %q: %w", file.Name, readErr)
		}
		parsed, parseErr := s.parser.Parse(data)
		if parseErr != nil {
			return 0, fmt.Errorf("dbinit: parse seed file %q: %w", file.Name, parseErr)
		}
		records = append(records, parsed...)
	}
	existingIDs, err := s.store.ExistingSeedIDs(ctx)
	if err != nil {
		return 0, fmt.Errorf("dbinit: read existing seed ids: %w", err)
	}
	seen := make(map[string]struct{}, len(existingIDs)+len(records))
	for _, id := range existingIDs {
		seen[id] = struct{}{}
	}
	inserted := 0
	for _, record := range records {
		id := strings.TrimSpace(s.id(record))
		if id == "" {
			return inserted, errors.New("dbinit: seed record id is required")
		}
		if _, exists := seen[id]; exists {
			continue
		}
		created, err := s.store.InsertSeed(ctx, record)
		if err != nil {
			return inserted, fmt.Errorf("dbinit: insert seed %q: %w", id, err)
		}
		seen[id] = struct{}{}
		if created {
			inserted++
		}
	}
	return inserted, nil
}
