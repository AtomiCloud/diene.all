package config_test

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/AtomiCloud/diene.go-config/lib/config"
)

// sampleHTTP, sampleCache, and sampleService are the typed models the committed
// sample service block is generated from, so config/config.schema.json is
// deterministically derived from Go types rather than hand-authored.
type sampleHTTP struct {
	Host string `json:"host" jsonschema:"minLength=1"`
	Port int    `json:"port" jsonschema:"minimum=1,maximum=65535"`
}

type sampleCache struct {
	Region   string `json:"region" jsonschema:"minLength=1"`
	Replicas []int  `json:"replicas,omitempty"`
	Secret   string `json:"secret,omitempty"`
}

type sampleService struct {
	HTTP  sampleHTTP  `json:"http"`
	Cache sampleCache `json:"cache"`
}

// sampleServiceSchema composes the config-owned app block with the typed sample
// service block. It is the single source the committed artifact is generated
// from and the drift gate regenerates.
func sampleServiceSchema(t *testing.T) config.Schema {
	t.Helper()
	fragment, err := config.FragmentFromType(sampleService{})
	if err != nil {
		t.Fatalf("fragment: %v", err)
	}
	// A mounted block is a subschema, not a resource root; drop the reflected
	// meta-schema markers so it composes cleanly.
	delete(fragment, "$schema")
	delete(fragment, "$id")
	return config.ComposeSchema(config.AppBlockSchema(), config.NewBlock("service", true, fragment))
}

// canonicalJSON re-marshals a JSON document into deterministic bytes (Go sorts
// object keys), so two documents compare equal by content regardless of
// presentation. It lets treefmt own the committed artifact's formatting while
// the drift gate still proves generated-content identity.
func canonicalJSON(t *testing.T, raw []byte) []byte {
	t.Helper()
	var value any
	if err := json.Unmarshal(raw, &value); err != nil {
		t.Fatalf("decode json: %v", err)
	}
	out, err := json.Marshal(value)
	if err != nil {
		t.Fatalf("re-marshal json: %v", err)
	}
	return out
}

// TestConfigSchemaArtifactIsFresh is the drift gate: the committed
// config/config.schema.json must be content-identical to the schema regenerated
// from the typed sample blocks. Both are re-marshaled to canonical bytes so the
// comparison is deterministic and independent of prettier's formatting.
// Regenerate with UPDATE_CONFIG_SCHEMA=1 when the source changes.
func TestConfigSchemaArtifactIsFresh(t *testing.T) {
	t.Parallel()
	path := filepath.Join(repoRoot, "config", "config.schema.json")

	generated, err := sampleServiceSchema(t).Marshal()
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	if os.Getenv("UPDATE_CONFIG_SCHEMA") == "1" {
		if writeErr := os.WriteFile(path, append(generated, '\n'), 0o600); writeErr != nil {
			t.Fatalf("update artifact: %v", writeErr)
		}
	}

	committed, err := os.ReadFile(path) //nolint:gosec // path is a fixed in-repo artifact
	if err != nil {
		t.Fatalf("read committed schema: %v", err)
	}
	if !bytes.Equal(canonicalJSON(t, committed), canonicalJSON(t, generated)) {
		t.Fatal("config/config.schema.json is stale; regenerate with UPDATE_CONFIG_SCHEMA=1")
	}
}
