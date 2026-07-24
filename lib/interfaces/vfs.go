package interfaces

import (
	"context"
	"time"
)

// VfsEntryType identifies the kind of a virtual filesystem entry.
type VfsEntryType string

const (
	// VfsEntryTypeFile identifies a regular file.
	VfsEntryTypeFile VfsEntryType = "file"
	// VfsEntryTypeDirectory identifies a directory.
	VfsEntryTypeDirectory VfsEntryType = "directory"
	// VfsEntryTypeLink identifies a symbolic link.
	VfsEntryTypeLink VfsEntryType = "link"
)

// String returns the portable wire name of t.
func (t VfsEntryType) String() string { return string(t) }

// VfsEntry is metadata for one virtual filesystem entry.
type VfsEntry struct {
	// Path is the implementation-owned opaque path of the entry.
	Path string
	// Type is the kind of the entry.
	Type VfsEntryType
	// Size is the entry size in bytes.
	Size int64
	// ModifiedAt is absent when the implementation has no modification time.
	ModifiedAt *time.Time
}

// NewVfsEntry builds an entry and copies modifiedAt when present.
func NewVfsEntry(path string, entryType VfsEntryType, size int64, modifiedAt *time.Time) VfsEntry {
	entry := VfsEntry{Path: path, Type: entryType, Size: size}
	if modifiedAt != nil {
		copied := modifiedAt.UTC()
		entry.ModifiedAt = &copied
	}
	return entry
}

// WriteOptions configures a write operation.
type WriteOptions struct {
	// CreateParents creates missing parent directories before writing.
	CreateParents bool
}

// VfsWriteOptions is the explicit name for WriteOptions when a package uses
// more than one family of option types.
type VfsWriteOptions = WriteOptions

// ListOptions configures a list operation.
type ListOptions struct {
	// Recursive includes descendants instead of only direct children.
	Recursive bool
}

// VfsListOptions is the explicit name for ListOptions when needed at call sites.
type VfsListOptions = ListOptions

// DirectoryOptions configures create and delete directory operations.
type DirectoryOptions struct {
	// Recursive creates missing ancestors or deletes descendants, as appropriate.
	Recursive bool
}

// VfsDirectoryOptions is the explicit name for DirectoryOptions when needed at
// call sites.
type VfsDirectoryOptions = DirectoryOptions

// Vfs is a portable virtual filesystem boundary. Paths are opaque strings;
// normalization and sandbox policy belong to implementations. Every non-nil
// error returned by an implementation must be problem-typed.
type Vfs interface {
	// Exists reports whether path names an entry.
	Exists(ctx context.Context, path string) (bool, error)
	// ReadBytes reads a file as bytes.
	ReadBytes(ctx context.Context, path string) ([]byte, error)
	// ReadText reads a UTF-8 text file.
	ReadText(ctx context.Context, path string) (string, error)
	// WriteBytes writes bytes to a file.
	WriteBytes(ctx context.Context, path string, bytes []byte, options WriteOptions) error
	// WriteText writes text to a file.
	WriteText(ctx context.Context, path string, content string, options WriteOptions) error
	// List returns entries below a directory.
	List(ctx context.Context, path string, options ListOptions) ([]VfsEntry, error)
	// CreateDirectory creates a directory.
	CreateDirectory(ctx context.Context, path string, options DirectoryOptions) error
	// Delete removes a file or directory.
	Delete(ctx context.Context, path string, options DirectoryOptions) error
}
