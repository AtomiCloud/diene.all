// Package vfsstore holds the stateful, byte-backed virtual filesystem
// algorithms behind the testhelper InMemoryVfs. It is the cohesive home for
// path normalization, parent resolution, and the write/list/create/delete
// storage behavior, exposed through a small exported API so the logic is
// black-box testable independently of the synchronized, scriptable adapter
// that wraps it. The store is not safe for concurrent use; its adapter owns
// synchronization.
package vfsstore

import (
	"slices"
	"strings"

	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
	"github.com/AtomiCloud/diene.go-interfaces/testhelper/internal/faults"
)

// Store is a byte-backed virtual filesystem. Files map normalized paths to
// their contents and directories is the set of present directories; root is
// always present.
type Store struct {
	files       map[string][]byte
	directories map[string]struct{}
}

// New creates an empty store containing only the root directory.
func New() *Store {
	return &Store{files: map[string][]byte{}, directories: map[string]struct{}{"/": {}}}
}

// Seed inserts initial files and directories, normalizing every path and
// copying file contents so the store never aliases caller-owned bytes.
func (s *Store) Seed(files map[string][]byte, directories []string) {
	for path, bytes := range files {
		s.files[Normalize(path)] = append([]byte(nil), bytes...)
	}
	for _, directory := range directories {
		s.directories[Normalize(directory)] = struct{}{}
	}
}

// Exists reports whether path names a stored file or directory.
func (s *Store) Exists(path string) bool {
	normalized := Normalize(path)
	_, file := s.files[normalized]
	_, directory := s.directories[normalized]
	return file || directory
}

// ReadBytes returns an independent copy of the file at path, or a
// path-not-found fault when it is absent.
func (s *Store) ReadBytes(path string) ([]byte, error) {
	normalized := Normalize(path)
	bytes, ok := s.files[normalized]
	if !ok {
		return nil, faults.PathNotFound(normalized)
	}
	return append([]byte(nil), bytes...), nil
}

// ReadText returns the file at path as text, or a path-not-found fault when it
// is absent.
func (s *Store) ReadText(path string) (string, error) {
	normalized := Normalize(path)
	bytes, ok := s.files[normalized]
	if !ok {
		return "", faults.PathNotFound(normalized)
	}
	return string(bytes), nil
}

// Write stores a copy of bytes at path, creating missing parents when
// options.CreateParents is set and otherwise faulting on an absent parent.
func (s *Store) Write(path string, bytes []byte, options interfaces.WriteOptions) error {
	normalized := Normalize(path)
	parentPath := Parent(normalized)
	if _, ok := s.directories[parentPath]; !ok {
		if !options.CreateParents {
			return faults.PathNotFound(parentPath)
		}
		s.CreateParents(parentPath)
	}
	s.files[normalized] = append([]byte(nil), bytes...)
	return nil
}

// List returns the entries below the directory at path, sorted by path. A
// non-recursive list yields only direct children; an absent directory faults.
func (s *Store) List(path string, options interfaces.ListOptions) ([]interfaces.VfsEntry, error) {
	normalized := Normalize(path)
	if _, ok := s.directories[normalized]; !ok {
		return nil, faults.PathNotFound(normalized)
	}
	prefix := normalized
	if prefix != "/" {
		prefix += "/"
	}
	entries := make([]interfaces.VfsEntry, 0)
	for directory := range s.directories {
		if directory != normalized && strings.HasPrefix(directory, prefix) && (options.Recursive || !strings.Contains(strings.TrimPrefix(directory, prefix), "/")) {
			entries = append(entries, interfaces.NewVfsEntry(directory, interfaces.VfsEntryTypeDirectory, 0, nil))
		}
	}
	for file, bytes := range s.files {
		if strings.HasPrefix(file, prefix) && (options.Recursive || !strings.Contains(strings.TrimPrefix(file, prefix), "/")) {
			entries = append(entries, interfaces.NewVfsEntry(file, interfaces.VfsEntryTypeFile, int64(len(bytes)), nil))
		}
	}
	slices.SortFunc(entries, func(left, right interfaces.VfsEntry) int { return strings.Compare(left.Path, right.Path) })
	return entries, nil
}

// CreateDirectory creates the directory at path. Without options.Recursive the
// parent must already exist; with it, missing ancestors are created too.
func (s *Store) CreateDirectory(path string, options interfaces.DirectoryOptions) error {
	normalized := Normalize(path)
	parentPath := Parent(normalized)
	if _, ok := s.directories[parentPath]; !ok && !options.Recursive {
		return faults.PathNotFound(parentPath)
	}
	if options.Recursive {
		s.CreateParents(normalized)
	} else {
		s.directories[normalized] = struct{}{}
	}
	return nil
}

// Delete removes the file or directory at path. A non-empty directory faults
// unless options.Recursive is set, in which case its descendants are removed;
// root is always preserved.
func (s *Store) Delete(path string, options interfaces.DirectoryOptions) error {
	normalized := Normalize(path)
	if _, ok := s.files[normalized]; ok {
		delete(s.files, normalized)
		return nil
	}
	if _, ok := s.directories[normalized]; !ok {
		return faults.PathNotFound(normalized)
	}
	prefix := normalized
	if prefix != "/" {
		prefix += "/"
	}
	for file := range s.files {
		if strings.HasPrefix(file, prefix) && !options.Recursive {
			return faults.DirectoryNotEmpty(normalized)
		}
	}
	for directory := range s.directories {
		if directory != normalized && strings.HasPrefix(directory, prefix) && !options.Recursive {
			return faults.DirectoryNotEmpty(normalized)
		}
	}
	for file := range s.files {
		if strings.HasPrefix(file, prefix) {
			delete(s.files, file)
		}
	}
	for directory := range s.directories {
		if directory == normalized || strings.HasPrefix(directory, prefix) {
			delete(s.directories, directory)
		}
	}
	s.directories["/"] = struct{}{}
	return nil
}

// Files returns an independently owned snapshot of file contents keyed by
// normalized path.
func (s *Store) Files() map[string][]byte {
	copied := make(map[string][]byte, len(s.files))
	for path, bytes := range s.files {
		copied[path] = append([]byte(nil), bytes...)
	}
	return copied
}

// Directories returns a sorted, independently owned snapshot of directory paths.
func (s *Store) Directories() []string {
	directories := make([]string, 0, len(s.directories))
	for directory := range s.directories {
		directories = append(directories, directory)
	}
	slices.Sort(directories)
	return directories
}

// CreateParents ensures every ancestor directory of path (and root) is present.
func (s *Store) CreateParents(path string) {
	var current strings.Builder
	for segment := range strings.SplitSeq(path, "/") {
		if segment != "" {
			current.WriteByte('/')
			current.WriteString(segment)
			s.directories[current.String()] = struct{}{}
		}
	}
	s.directories["/"] = struct{}{}
}

// Normalize collapses a path to its canonical absolute form: a leading slash
// and single-slash-separated non-empty segments.
func Normalize(path string) string {
	segments := make([]string, 0)
	for segment := range strings.SplitSeq(path, "/") {
		if segment != "" {
			segments = append(segments, segment)
		}
	}
	return "/" + strings.Join(segments, "/")
}

// Parent returns the parent directory of a normalized path; root is its own
// parent.
func Parent(path string) string {
	if path == "/" {
		return "/"
	}
	index := strings.LastIndex(path, "/")
	if index == 0 {
		return "/"
	}
	return path[:index]
}
