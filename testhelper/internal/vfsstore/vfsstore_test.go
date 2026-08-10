package vfsstore_test

import (
	"slices"
	"testing"

	probtest "github.com/AtomiCloud/diene.go-errors-problems/testhelper"
	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
	"github.com/AtomiCloud/diene.go-interfaces/testhelper/internal/vfsstore"
)

// TestNormalize proves path normalization collapses empty segments to the
// canonical absolute form.
func TestNormalize(t *testing.T) {
	cases := map[string]string{
		"":            "/",
		"/":           "/",
		"//a//file":   "/a/file",
		"a/b/":        "/a/b",
		"/a/b/../c/d": "/a/b/../c/d", // normalization is lexical over separators only.
	}
	for input, want := range cases {
		if got := vfsstore.Normalize(input); got != want {
			t.Fatalf("Normalize(%q) = %q, want %q", input, got, want)
		}
	}
}

// TestParent proves parent resolution, with root as its own parent.
func TestParent(t *testing.T) {
	cases := map[string]string{
		"/":       "/",
		"/file":   "/",
		"/a/file": "/a",
		"/a/b/c":  "/a/b",
	}
	for input, want := range cases {
		if got := vfsstore.Parent(input); got != want {
			t.Fatalf("Parent(%q) = %q, want %q", input, got, want)
		}
	}
}

// TestReadWriteAndExists proves seeding, reads with copy isolation, writes with
// and without parent creation, and the path-not-found faults.
func TestReadWriteAndExists(t *testing.T) {
	store := vfsstore.New()
	store.Seed(map[string][]byte{"//a//file": []byte("text")}, []string{"/a", "/a/sub"})

	if !store.Exists("/a/file") || store.Exists("/nope") {
		t.Fatal("Exists mismatch")
	}

	bytes, err := store.ReadBytes("/a/file")
	if err != nil || string(bytes) != "text" {
		t.Fatalf("ReadBytes: %q %v", bytes, err)
	}
	bytes[0] = 'x'
	if again, _ := store.ReadBytes("/a/file"); string(again) != "text" {
		t.Fatal("ReadBytes must not alias stored state")
	}
	text, err := store.ReadText("/a/file")
	if err != nil || text != "text" {
		t.Fatalf("ReadText: %q %v", text, err)
	}
	probtest.AssertError(t, mustErr(store.ReadBytes("/missing")), probtest.ExpectID("path-not-found"), probtest.ExpectStatus(404))
	probtest.AssertError(t, mustTextErr(store.ReadText("/missing")), probtest.ExpectID("path-not-found"))

	if err := store.Write("/a/new", []byte("body"), interfaces.WriteOptions{}); err != nil {
		t.Fatal(err)
	}
	probtest.AssertError(t, store.Write("/missing/file", []byte("x"), interfaces.WriteOptions{}), probtest.ExpectID("path-not-found"))
	if err := store.Write("/deep/nested/file", []byte("y"), interfaces.WriteOptions{CreateParents: true}); err != nil {
		t.Fatal(err)
	}
	if !store.Exists("/deep/nested") {
		t.Fatal("CreateParents must materialize ancestors")
	}
}

// TestListAndDirectories proves direct and recursive listing, the missing-path
// fault, and independent directory snapshots.
func TestListAndDirectories(t *testing.T) {
	store := vfsstore.New()
	store.Seed(map[string][]byte{"/a/file": []byte("t")}, []string{"/a", "/a/sub"})

	direct, err := store.List("/a", interfaces.ListOptions{})
	if err != nil || len(direct) != 2 || direct[0].Path != "/a/file" || direct[1].Path != "/a/sub" {
		t.Fatalf("List direct: %#v %v", direct, err)
	}
	if direct[0].Type != interfaces.VfsEntryTypeFile || direct[0].Size != 1 {
		t.Fatalf("unexpected file entry: %#v", direct[0])
	}
	recursive, err := store.List("/", interfaces.ListOptions{Recursive: true})
	if err != nil || len(recursive) < 3 {
		t.Fatalf("List recursive: %#v %v", recursive, err)
	}
	probtest.AssertError(t, mustListErr(store.List("/missing", interfaces.ListOptions{})), probtest.ExpectID("path-not-found"))

	dirs := store.Directories()
	if !slices.Contains(dirs, "/") || !slices.Contains(dirs, "/a") || !slices.Contains(dirs, "/a/sub") {
		t.Fatalf("directories snapshot missing entries: %#v", dirs)
	}
	dirs[0] = "changed"
	if slices.Contains(store.Directories(), "changed") {
		t.Fatal("Directories must return an independent snapshot")
	}
	files := store.Files()
	files["/a/file"][0] = 'X'
	if again := store.Files(); string(again["/a/file"]) != "t" {
		t.Fatal("Files must return an independent snapshot")
	}
}

// TestCreateDirectory proves non-recursive creation, its missing-parent fault,
// and recursive ancestor creation.
func TestCreateDirectory(t *testing.T) {
	store := vfsstore.New()
	if err := store.CreateDirectory("/top", interfaces.DirectoryOptions{}); err != nil {
		t.Fatal(err)
	}
	probtest.AssertError(t, store.CreateDirectory("/none/child", interfaces.DirectoryOptions{}), probtest.ExpectID("path-not-found"))
	if err := store.CreateDirectory("/created/a/b", interfaces.DirectoryOptions{Recursive: true}); err != nil {
		t.Fatal(err)
	}
	if !store.Exists("/created/a") || !store.Exists("/created/a/b") {
		t.Fatal("recursive create must materialize every ancestor")
	}
}

// TestDelete proves file removal, both non-empty faults, recursive directory
// removal, root preservation, and the missing-path fault.
func TestDelete(t *testing.T) {
	store := vfsstore.New()
	store.Seed(map[string][]byte{"/a/file": []byte("t")}, []string{"/a", "/parent", "/parent/child"})

	probtest.AssertError(t, store.Delete("/missing", interfaces.DirectoryOptions{}), probtest.ExpectID("path-not-found"))
	probtest.AssertError(t, store.Delete("/a", interfaces.DirectoryOptions{}), probtest.ExpectID("directory-not-empty"), probtest.ExpectStatus(409))
	probtest.AssertError(t, store.Delete("/parent", interfaces.DirectoryOptions{}), probtest.ExpectID("directory-not-empty"))

	if err := store.Delete("/a/file", interfaces.DirectoryOptions{}); err != nil {
		t.Fatal(err)
	}
	if err := store.Delete("/a", interfaces.DirectoryOptions{Recursive: true}); err != nil {
		t.Fatal(err)
	}
	if store.Exists("/a") {
		t.Fatal("recursive delete must remove the directory")
	}

	root := vfsstore.New()
	root.Seed(map[string][]byte{"/child/file": []byte("x")}, []string{"/child"})
	if err := root.Delete("/", interfaces.DirectoryOptions{Recursive: true}); err != nil {
		t.Fatal(err)
	}
	if !root.Exists("/") {
		t.Fatal("root must be preserved after a recursive delete")
	}
	if root.Exists("/child") {
		t.Fatal("recursive delete from root must clear descendants")
	}
}

func mustErr(_ []byte, err error) error { return err }

func mustTextErr(_ string, err error) error { return err }

func mustListErr(_ []interfaces.VfsEntry, err error) error { return err }
