package filesystem_test

import (
	"context"
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"testing"

	"github.com/AtomiCloud/diene.go-e2e/adapters/filesystem"
	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
)

// These are integration tests against the REAL filesystem. The unit tier drives
// fixture materialization through the interfaces sibling's in-memory filesystem,
// so this is the only place the host binding itself is proven.

func TestExistsAnswersWithoutFailing(t *testing.T) {
	t.Parallel()

	vfs := filesystem.NewVfs()
	directory := t.TempDir()
	present := filepath.Join(directory, "present")
	if err := os.WriteFile(present, []byte("x"), 0o600); err != nil {
		t.Fatalf("WriteFile() error = %v", err)
	}
	found, err := vfs.Exists(context.Background(), present)
	if err != nil || !found {
		t.Fatalf("Exists(present) = %v, %v, want true", found, err)
	}
	found, err = vfs.Exists(context.Background(), filepath.Join(directory, "absent"))
	if err != nil {
		t.Fatalf("Exists(absent) error = %v, want an absent path to be an answer", err)
	}
	if found {
		t.Fatal("Exists(absent) = true, want false")
	}
}

func TestExistsSurfacesARealStatFailure(t *testing.T) {
	t.Parallel()

	vfs := filesystem.NewVfs()
	directory := t.TempDir()
	notADirectory := filepath.Join(directory, "file")
	if err := os.WriteFile(notADirectory, []byte("x"), 0o600); err != nil {
		t.Fatalf("WriteFile() error = %v", err)
	}
	_, err := vfs.Exists(context.Background(), filepath.Join(notADirectory, "child"))
	if err == nil {
		t.Fatal("Exists() error = nil, want the ENOTDIR failure surfaced")
	}
	if errors.Is(err, os.ErrNotExist) {
		t.Fatalf("Exists() error = %v, want it distinguished from a plain absence", err)
	}
}

func TestWriteAndReadRoundTripAsBytesAndText(t *testing.T) {
	t.Parallel()

	vfs := filesystem.NewVfs()
	directory := t.TempDir()
	nested := filepath.Join(directory, "deep", "nested", "config.yaml")

	err := vfs.WriteBytes(context.Background(), nested, []byte("app: one\n"), interfaces.WriteOptions{CreateParents: true})
	if err != nil {
		t.Fatalf("WriteBytes() error = %v", err)
	}
	content, err := vfs.ReadBytes(context.Background(), nested)
	if err != nil || string(content) != "app: one\n" {
		t.Fatalf("ReadBytes() = %q, %v, want the written bytes", content, err)
	}

	err = vfs.WriteText(context.Background(), nested, "app: two\n", interfaces.WriteOptions{})
	if err != nil {
		t.Fatalf("WriteText() error = %v", err)
	}
	text, err := vfs.ReadText(context.Background(), nested)
	if err != nil || text != "app: two\n" {
		t.Fatalf("ReadText() = %q, %v, want the overwritten text", text, err)
	}

	info, err := os.Stat(nested)
	if err != nil {
		t.Fatalf("Stat() error = %v", err)
	}
	if info.Mode().Perm() != fs.FileMode(0o600) {
		t.Fatalf("mode = %v, want owner-only because a fixture carries injected secrets", info.Mode().Perm())
	}
}

func TestWriteRefusesAMissingParentWithoutPermission(t *testing.T) {
	t.Parallel()

	vfs := filesystem.NewVfs()
	target := filepath.Join(t.TempDir(), "absent", "config.yaml")
	err := vfs.WriteBytes(context.Background(), target, []byte("x"), interfaces.WriteOptions{})
	if err == nil {
		t.Fatal("WriteBytes() error = nil, want the missing parent surfaced")
	}
}

func TestWriteSurfacesAnUncreatableParent(t *testing.T) {
	t.Parallel()

	vfs := filesystem.NewVfs()
	directory := t.TempDir()
	blocker := filepath.Join(directory, "blocker")
	if err := os.WriteFile(blocker, []byte("x"), 0o600); err != nil {
		t.Fatalf("WriteFile() error = %v", err)
	}
	err := vfs.WriteBytes(
		context.Background(),
		filepath.Join(blocker, "child", "config.yaml"),
		[]byte("x"),
		interfaces.WriteOptions{CreateParents: true},
	)
	if err == nil {
		t.Fatal("WriteBytes() error = nil, want the uncreatable parent surfaced")
	}
}

func TestReadSurfacesAMissingFile(t *testing.T) {
	t.Parallel()

	vfs := filesystem.NewVfs()
	if _, err := vfs.ReadBytes(context.Background(), filepath.Join(t.TempDir(), "absent")); err == nil {
		t.Fatal("ReadBytes() error = nil, want the absence surfaced")
	}
	if _, err := vfs.ReadText(context.Background(), filepath.Join(t.TempDir(), "absent")); err == nil {
		t.Fatal("ReadText() error = nil, want the absence surfaced")
	}
}

func TestCreateDirectoryHonoursRecursion(t *testing.T) {
	t.Parallel()

	vfs := filesystem.NewVfs()
	root := t.TempDir()

	shallow := filepath.Join(root, "one")
	if err := vfs.CreateDirectory(context.Background(), shallow, interfaces.DirectoryOptions{}); err != nil {
		t.Fatalf("CreateDirectory() error = %v", err)
	}
	info, err := os.Stat(shallow)
	if err != nil || !info.IsDir() {
		t.Fatalf("Stat() = %v, %v, want a directory", info, err)
	}
	if info.Mode().Perm() != fs.FileMode(0o700) {
		t.Fatalf("mode = %v, want owner-only", info.Mode().Perm())
	}

	if err := vfs.CreateDirectory(context.Background(), filepath.Join(root, "a", "b", "c"), interfaces.DirectoryOptions{}); err == nil {
		t.Fatal("CreateDirectory() error = nil, want a non-recursive create to refuse missing parents")
	}
	deep := filepath.Join(root, "a", "b", "c")
	if err := vfs.CreateDirectory(context.Background(), deep, interfaces.DirectoryOptions{Recursive: true}); err != nil {
		t.Fatalf("CreateDirectory(recursive) error = %v", err)
	}
	if info, err := os.Stat(deep); err != nil || !info.IsDir() {
		t.Fatalf("Stat() = %v, %v, want the whole chain created", info, err)
	}
}

func TestDeleteHonoursRecursion(t *testing.T) {
	t.Parallel()

	vfs := filesystem.NewVfs()
	root := t.TempDir()
	file := filepath.Join(root, "file")
	if err := os.WriteFile(file, []byte("x"), 0o600); err != nil {
		t.Fatalf("WriteFile() error = %v", err)
	}
	if err := vfs.Delete(context.Background(), file, interfaces.DirectoryOptions{}); err != nil {
		t.Fatalf("Delete() error = %v", err)
	}

	populated := filepath.Join(root, "populated")
	if err := os.MkdirAll(filepath.Join(populated, "child"), 0o700); err != nil {
		t.Fatalf("MkdirAll() error = %v", err)
	}
	if err := vfs.Delete(context.Background(), populated, interfaces.DirectoryOptions{}); err == nil {
		t.Fatal("Delete() error = nil, want a non-recursive delete to refuse a populated directory")
	}
	if err := vfs.Delete(context.Background(), populated, interfaces.DirectoryOptions{Recursive: true}); err != nil {
		t.Fatalf("Delete(recursive) error = %v", err)
	}
	if _, err := os.Stat(populated); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("Stat() error = %v, want the tree gone", err)
	}
}

func TestListDescribesEntriesInAStableOrder(t *testing.T) {
	t.Parallel()

	vfs := filesystem.NewVfs()
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, "nested"), 0o700); err != nil {
		t.Fatalf("MkdirAll() error = %v", err)
	}
	if err := os.WriteFile(filepath.Join(root, "top.yaml"), []byte("top"), 0o600); err != nil {
		t.Fatalf("WriteFile() error = %v", err)
	}
	if err := os.WriteFile(filepath.Join(root, "nested", "inner.yaml"), []byte("inner"), 0o600); err != nil {
		t.Fatalf("WriteFile() error = %v", err)
	}
	if err := os.Symlink(filepath.Join(root, "top.yaml"), filepath.Join(root, "link.yaml")); err != nil {
		t.Fatalf("Symlink() error = %v", err)
	}

	shallow, err := vfs.List(context.Background(), root, interfaces.ListOptions{})
	if err != nil {
		t.Fatalf("List() error = %v", err)
	}
	if len(shallow) != 3 {
		t.Fatalf("List() = %+v, want the three immediate children", shallow)
	}
	kinds := map[string]interfaces.VfsEntryType{}
	for _, entry := range shallow {
		kinds[filepath.Base(entry.Path)] = entry.Type
	}
	if kinds["nested"] != interfaces.VfsEntryTypeDirectory {
		t.Fatalf("nested = %q, want a directory", kinds["nested"])
	}
	if kinds["top.yaml"] != interfaces.VfsEntryTypeFile {
		t.Fatalf("top.yaml = %q, want a file", kinds["top.yaml"])
	}
	if kinds["link.yaml"] != interfaces.VfsEntryTypeLink {
		t.Fatalf("link.yaml = %q, want a link", kinds["link.yaml"])
	}

	recursive, err := vfs.List(context.Background(), root, interfaces.ListOptions{Recursive: true})
	if err != nil {
		t.Fatalf("List(recursive) error = %v", err)
	}
	if len(recursive) != 4 {
		t.Fatalf("List(recursive) = %+v, want every descendant and not the root itself", recursive)
	}
	for index := 1; index < len(recursive); index++ {
		if recursive[index-1].Path >= recursive[index].Path {
			t.Fatalf("List(recursive) = %+v, want a stable sorted order", recursive)
		}
	}
	for _, entry := range recursive {
		if entry.ModifiedAt == nil {
			t.Fatalf("entry %q has no modification time", entry.Path)
		}
	}
}

func TestListSurfacesAMissingDirectory(t *testing.T) {
	t.Parallel()

	vfs := filesystem.NewVfs()
	absent := filepath.Join(t.TempDir(), "absent")
	if _, err := vfs.List(context.Background(), absent, interfaces.ListOptions{}); err == nil {
		t.Fatal("List() error = nil, want the absence surfaced")
	}
	if _, err := vfs.List(context.Background(), absent, interfaces.ListOptions{Recursive: true}); err == nil {
		t.Fatal("List(recursive) error = nil, want the absence surfaced")
	}
}
