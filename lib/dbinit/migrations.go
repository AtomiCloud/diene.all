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

// MigrationStore persists Postgres migration state.
type MigrationStore interface {
	PrepareMigrations(ctx context.Context) error
	AppliedMigrations(ctx context.Context) ([]string, error)
	ApplyMigration(ctx context.Context, name string, statement string) error
}

// MarkerStore persists the Redis migration marker idempotently.
type MarkerStore interface {
	SetIfAbsent(ctx context.Context, key string, value string) (bool, error)
}

// MigrationFile is one validated SQL migration found through the VFS seam.
type MigrationFile struct {
	Name string
	Path string
}

// ValidMigrationName reports whether name follows NNN_name.sql.
func ValidMigrationName(name string) bool {
	if !strings.HasSuffix(name, ".sql") {
		return false
	}
	stem := strings.TrimSuffix(name, ".sql")
	index := 0
	for index < len(stem) && stem[index] >= '0' && stem[index] <= '9' {
		index++
	}
	if index == 0 || index >= len(stem)-1 || (stem[index] != '-' && stem[index] != '_') {
		return false
	}
	for _, character := range stem[index+1:] {
		if (character >= 'a' && character <= 'z') ||
			(character >= '0' && character <= '9') || character == '-' || character == '_' {
			continue
		}
		return false
	}
	return true
}

// MigrationFiles filters, validates, and sorts direct VFS entries.
func MigrationFiles(entries []interfaces.VfsEntry) ([]MigrationFile, error) {
	files := make([]MigrationFile, 0, len(entries))
	for _, entry := range entries {
		if entry.Type != interfaces.VfsEntryTypeFile {
			continue
		}
		name := path.Base(entry.Path)
		if !strings.HasSuffix(name, ".sql") {
			continue
		}
		if !ValidMigrationName(name) {
			return nil, fmt.Errorf("dbinit: invalid migration name %q", name)
		}
		files = append(files, MigrationFile{Name: name, Path: entry.Path})
	}
	slices.SortFunc(files, func(left, right MigrationFile) int { return strings.Compare(left.Name, right.Name) })
	return files, nil
}

// MigrationOptions configures a MigrationRunner.
type MigrationOptions struct {
	Filesystem interfaces.Vfs
	Postgres   MigrationStore
	Redis      MarkerStore
	Directory  string
	MarkerKey  string
}

// MigrationRunner applies missing Postgres migrations and a Redis marker.
type MigrationRunner struct {
	filesystem interfaces.Vfs
	postgres   MigrationStore
	redis      MarkerStore
	directory  string
	markerKey  string
}

// NewMigrationRunner creates an injected migration runner.
func NewMigrationRunner(options MigrationOptions) (*MigrationRunner, error) {
	if options.Filesystem == nil {
		return nil, errors.New("dbinit: migration filesystem is required")
	}
	if options.Postgres == nil {
		return nil, errors.New("dbinit: migration postgres store is required")
	}
	if options.Redis == nil {
		return nil, errors.New("dbinit: migration marker store is required")
	}
	if strings.TrimSpace(options.Directory) == "" {
		return nil, errors.New("dbinit: migration directory is required")
	}
	if strings.TrimSpace(options.MarkerKey) == "" {
		return nil, errors.New("dbinit: redis migration key is required")
	}
	return &MigrationRunner{
		filesystem: options.Filesystem,
		postgres:   options.Postgres,
		redis:      options.Redis,
		directory:  options.Directory,
		markerKey:  options.MarkerKey,
	}, nil
}

// Run applies each missing migration in lexical order and writes the marker.
func (m *MigrationRunner) Run(ctx context.Context) error {
	if err := m.postgres.PrepareMigrations(ctx); err != nil {
		return fmt.Errorf("dbinit: prepare migration ledger: %w", err)
	}
	appliedNames, err := m.postgres.AppliedMigrations(ctx)
	if err != nil {
		return fmt.Errorf("dbinit: read migration ledger: %w", err)
	}
	applied := make(map[string]struct{}, len(appliedNames))
	for _, name := range appliedNames {
		applied[name] = struct{}{}
	}
	entries, err := m.filesystem.List(ctx, m.directory, interfaces.ListOptions{})
	if err != nil {
		return fmt.Errorf("dbinit: list migrations: %w", err)
	}
	files, err := MigrationFiles(entries)
	if err != nil {
		return err
	}
	for _, file := range files {
		if _, exists := applied[file.Name]; exists {
			continue
		}
		statement, err := m.filesystem.ReadText(ctx, file.Path)
		if err != nil {
			return fmt.Errorf("dbinit: read migration %q: %w", file.Name, err)
		}
		if strings.TrimSpace(statement) == "" {
			return fmt.Errorf("dbinit: migration %q is empty", file.Name)
		}
		if err := m.postgres.ApplyMigration(ctx, file.Name, statement); err != nil {
			return fmt.Errorf("dbinit: apply migration %q: %w", file.Name, err)
		}
	}
	if _, err := m.redis.SetIfAbsent(ctx, m.markerKey, "ready"); err != nil {
		return fmt.Errorf("dbinit: write redis migration marker: %w", err)
	}
	return nil
}
