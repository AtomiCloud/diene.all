package filesystem_test

import (
	"context"
	"fmt"
	"os"
	"path/filepath"

	"github.com/AtomiCloud/diene.go-e2e/adapters/filesystem"
	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
)

func ExampleNewVfs() {
	vfs := filesystem.NewVfs()
	root, err := os.MkdirTemp("", "diene-e2e-example-")
	if err != nil {
		panic(err)
	}
	defer func() { _ = os.RemoveAll(root) }()

	target := filepath.Join(root, "config", "base.yaml")
	if writeErr := vfs.WriteText(context.Background(), target, "app: billing\n", interfaces.WriteOptions{CreateParents: true}); writeErr != nil {
		panic(writeErr)
	}
	present, err := vfs.Exists(context.Background(), target)
	if err != nil {
		panic(err)
	}
	content, err := vfs.ReadText(context.Background(), target)
	if err != nil {
		panic(err)
	}
	fmt.Print(present, " ", content)
	// Output: true app: billing
}

func ExampleVfs_Exists() {
	vfs := filesystem.NewVfs()
	// An absent path is an answer, not a failure.
	present, err := vfs.Exists(context.Background(), filepath.Join(os.TempDir(), "diene-e2e-absent"))
	fmt.Println(present, err)
	// Output: false <nil>
}

func ExampleVfs_List() {
	vfs := filesystem.NewVfs()
	root, err := os.MkdirTemp("", "diene-e2e-example-")
	if err != nil {
		panic(err)
	}
	defer func() { _ = os.RemoveAll(root) }()

	for _, name := range []string{"garden.yaml", "base.yaml"} {
		if writeErr := vfs.WriteText(context.Background(), filepath.Join(root, name), "{}\n", interfaces.WriteOptions{}); writeErr != nil {
			panic(writeErr)
		}
	}
	entries, err := vfs.List(context.Background(), root, interfaces.ListOptions{})
	if err != nil {
		panic(err)
	}
	for _, entry := range entries {
		fmt.Println(filepath.Base(entry.Path), entry.Type)
	}
	// Output:
	// base.yaml file
	// garden.yaml file
}
