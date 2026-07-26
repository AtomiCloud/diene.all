package filesystem

import (
	"context"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
)

// Permissions the harness creates fixture files and directories with.
//
// A fixture holds injected credentials, so it is owner-only. Nothing in a SIT
// run needs another account to read the environment a test was handed.
const (
	// FilePermissions is the mode a written fixture file carries.
	FilePermissions fs.FileMode = 0o600
	// DirectoryPermissions is the mode a created fixture directory carries.
	DirectoryPermissions fs.FileMode = 0o700
)

// Vfs is the process-backed filesystem seam and satisfies [interfaces.Vfs].
//
// It is a value type with no mutable state, so one instance is safe to share
// across a whole suite.
type Vfs struct{}

// NewVfs returns the process-backed filesystem seam.
func NewVfs() Vfs {
	return Vfs{}
}

// Exists reports whether path is present.
//
// An absent path is NOT an error: "does the artifact exist" is a question, and
// answering it with a failure would force every caller to unwrap os errors.
func (Vfs) Exists(_ context.Context, path string) (bool, error) {
	_, err := os.Stat(path)
	if err == nil {
		return true, nil
	}
	if os.IsNotExist(err) {
		return false, nil
	}
	return false, err
}

// ReadBytes reads the whole file at path.
func (Vfs) ReadBytes(_ context.Context, path string) ([]byte, error) {
	return os.ReadFile(path) //nolint:gosec // the harness reads the fixtures it was told to read
}

// ReadText reads the whole file at path as text.
func (v Vfs) ReadText(ctx context.Context, path string) (string, error) {
	content, err := v.ReadBytes(ctx, path)
	if err != nil {
		return "", err
	}
	return string(content), nil
}

// WriteBytes writes content to path, creating parent directories when options
// asks for it.
func (Vfs) WriteBytes(_ context.Context, path string, content []byte, options interfaces.WriteOptions) error {
	if options.CreateParents {
		if err := os.MkdirAll(filepath.Dir(path), DirectoryPermissions); err != nil {
			return err
		}
	}
	return os.WriteFile(path, content, FilePermissions)
}

// WriteText writes content to path as text, creating parent directories when
// options asks for it.
func (v Vfs) WriteText(ctx context.Context, path string, content string, options interfaces.WriteOptions) error {
	return v.WriteBytes(ctx, path, []byte(content), options)
}

// List returns the entries under path, recursively when options asks for it.
//
// Both modes are one walk. A shallow listing simply refuses to descend, which
// keeps a single error path for an entry that cannot be read — two
// implementations would eventually disagree about what a listing failure is.
//
// Entries come back in a stable order so a failing SIT report can be diffed
// against a passing one.
func (Vfs) List(_ context.Context, path string, options interfaces.ListOptions) ([]interfaces.VfsEntry, error) {
	entries := []interfaces.VfsEntry{}
	walkErr := filepath.Walk(path, func(current string, info fs.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if current == path {
			return nil
		}
		entries = append(entries, describe(current, info))
		if !options.Recursive && info.IsDir() {
			return filepath.SkipDir
		}
		return nil
	})
	if walkErr != nil {
		return nil, walkErr
	}
	slices.SortFunc(entries, func(left interfaces.VfsEntry, right interfaces.VfsEntry) int {
		return strings.Compare(left.Path, right.Path)
	})
	return entries, nil
}

// CreateDirectory creates path, and its parents when options asks for it.
func (Vfs) CreateDirectory(_ context.Context, path string, options interfaces.DirectoryOptions) error {
	if options.Recursive {
		return os.MkdirAll(path, DirectoryPermissions)
	}
	return os.Mkdir(path, DirectoryPermissions)
}

// Delete removes path, and its contents when options asks for it.
func (Vfs) Delete(_ context.Context, path string, options interfaces.DirectoryOptions) error {
	if options.Recursive {
		return os.RemoveAll(path)
	}
	return os.Remove(path)
}

// describe renders one filesystem entry as the seam's value type.
func describe(path string, info fs.FileInfo) interfaces.VfsEntry {
	modified := info.ModTime()
	return interfaces.NewVfsEntry(path, entryType(info), info.Size(), &modified)
}

// entryType classifies one filesystem entry.
func entryType(info fs.FileInfo) interfaces.VfsEntryType {
	switch {
	case info.IsDir():
		return interfaces.VfsEntryTypeDirectory
	case info.Mode()&fs.ModeSymlink != 0:
		return interfaces.VfsEntryTypeLink
	default:
		return interfaces.VfsEntryTypeFile
	}
}
