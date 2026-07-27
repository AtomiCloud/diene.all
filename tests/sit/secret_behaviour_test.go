package sit_test

import (
	"path/filepath"
	"strings"
	"testing"

	"github.com/AtomiCloud/diene.go-e2e/adapters/filesystem"
	"github.com/AtomiCloud/diene.go-e2e/lib/e2e"
	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
)

func TestSecretBehaviourJourney(t *testing.T) {
	harness := newSITHarness(t)
	temporaryRoot := t.TempDir()
	configDirectory := filepath.Join(temporaryRoot, "config")
	vfs := filesystem.NewVfs()
	if err := vfs.CreateDirectory(t.Context(), configDirectory, interfaces.DirectoryOptions{Recursive: true}); err != nil {
		t.Fatalf("create temporary config directory: %v", err)
	}
	settings, err := vfs.ReadBytes(t.Context(), filepath.Join(harness.root, "config", "settings.yaml"))
	if err != nil {
		t.Fatalf("read base settings: %v", err)
	}
	const blankKey = "encryption:\n  key: ''"
	const fileKey = "encryption:\n  key: AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
	if strings.Count(string(settings), blankKey) != 1 {
		t.Fatal("base settings do not contain exactly one blank encryption key")
	}
	settings = []byte(strings.Replace(string(settings), blankKey, fileKey, 1))
	if writeErr := vfs.WriteBytes(
		t.Context(),
		filepath.Join(configDirectory, "settings.yaml"),
		settings,
		interfaces.WriteOptions{},
	); writeErr != nil {
		t.Fatalf("write temporary base settings: %v", writeErr)
	}
	overlay, err := vfs.ReadBytes(t.Context(), filepath.Join(harness.root, "config", "lapras.settings.yaml"))
	if err != nil {
		t.Fatalf("read landscape settings: %v", err)
	}
	if writeErr := vfs.WriteBytes(
		t.Context(),
		filepath.Join(configDirectory, "lapras.settings.yaml"),
		overlay,
		interfaces.WriteOptions{},
	); writeErr != nil {
		t.Fatalf("write temporary landscape settings: %v", writeErr)
	}
	id := newUUID(t)
	environment := workerEnvironment("secret", id)
	environment["ATOMI_ENCRYPTION__KEY"] = ""
	environment["GO_CONSUMER_ROOT"] = temporaryRoot
	journey := e2e.Journey{
		Name: "blank secret behavior",
		Steps: []e2e.Step{{
			Name:       "retain the nonblank file secret",
			Invocation: harness.invocation(environment, "worker", "--once"),
			Expect: e2e.Expectation{
				ExitCode:       0,
				StdoutExcludes: []string{"encryption key", "configuration"},
			},
		}},
	}
	harness.run(t, journey)
}
