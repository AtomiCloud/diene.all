package config_test

import (
	"encoding/json"
	"slices"
	"testing"

	"github.com/AtomiCloud/diene.go-config/lib/config"
)

func TestAppBlockSchemaShape(t *testing.T) {
	t.Parallel()
	block := config.AppBlockSchema()
	if block.Key != config.AppKey || !block.Required {
		t.Fatalf("app block metadata wrong: %+v", block)
	}
	if additional, ok := block.Schema["additionalProperties"].(bool); !ok || additional {
		t.Fatal("app block must reject unknown keys")
	}
	required, ok := block.Schema["required"].([]any)
	if !ok || len(required) != 5 {
		t.Fatalf("app block must require the full LPSMV tuple: %v", block.Schema["required"])
	}
}

// TestAppBlockSchemaAgreesWithReflectedType is the independent oracle: the
// shipped literal fragment and the invopop reflection of the AppBlock type must
// require the same field set, so the hand-authored schema cannot silently drift
// from the Go type.
func TestAppBlockSchemaAgreesWithReflectedType(t *testing.T) {
	t.Parallel()
	raw, err := config.GenerateSchema(config.AppBlock{})
	if err != nil {
		t.Fatalf("generate: %v", err)
	}
	var reflected map[string]any
	if err := json.Unmarshal(raw, &reflected); err != nil {
		t.Fatalf("unmarshal reflected: %v", err)
	}
	if got := requiredSet(reflected["required"]); !slices.Equal(got, requiredSet(config.AppBlockSchema().Schema["required"])) {
		t.Fatalf("reflected required set %v disagrees with shipped fragment", got)
	}
	reflectedProps, ok := reflected["properties"].(map[string]any)
	if !ok {
		t.Fatal("reflected schema must carry properties")
	}
	shippedProps, ok := config.AppBlockSchema().Schema["properties"].(map[string]any)
	if !ok {
		t.Fatal("shipped schema must carry properties")
	}
	if len(reflectedProps) != len(shippedProps) {
		t.Fatalf("property counts disagree: reflected %d shipped %d", len(reflectedProps), len(shippedProps))
	}
	for name := range shippedProps {
		if reflectedProps[name] == nil {
			t.Fatalf("reflected schema is missing property %q", name)
		}
	}
}

func requiredSet(value any) []string {
	entries, ok := value.([]any)
	if !ok {
		return nil
	}
	names := make([]string, 0, len(entries))
	for _, entry := range entries {
		if name, ok := entry.(string); ok {
			names = append(names, name)
		}
	}
	slices.Sort(names)
	return names
}
