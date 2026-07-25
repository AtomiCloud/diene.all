package config_test

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/AtomiCloud/diene.go-config/lib/config"
	"github.com/AtomiCloud/diene.go-config/testhelper"
)

func TestComposeSchemaMountsBlocksAndRequired(t *testing.T) {
	t.Parallel()
	schema := config.ComposeSchema(config.AppBlockSchema(), testhelper.DemoBlock())
	root := schema.Root()
	if root["$schema"] != config.Draft2020 {
		t.Fatalf("root must declare draft 2020-12, got %v", root["$schema"])
	}
	additional, isBool := root["additionalProperties"].(bool)
	if root["type"] != "object" || !isBool || !additional {
		t.Fatalf("root shape wrong: %v", root)
	}
	properties, ok := root["properties"].(map[string]any)
	if !ok || properties[config.AppKey] == nil || properties[testhelper.DemoBlockKey] == nil {
		t.Fatalf("both blocks must be mounted: %v", properties)
	}
	required, ok := root["required"].([]any)
	if !ok || len(required) != 2 {
		t.Fatalf("both required blocks must be listed: %v", root["required"])
	}
}

func TestComposeSchemaOmitsRequiredWhenNoneMandatory(t *testing.T) {
	t.Parallel()
	schema := config.ComposeSchema(config.NewBlock("optional", false, map[string]any{"type": "object"}))
	if _, present := schema.Root()["required"]; present {
		t.Fatal("required must be omitted when no block is mandatory")
	}
}

func TestGenerateSchemaReflectsGoType(t *testing.T) {
	t.Parallel()
	raw, err := config.GenerateSchema(config.AppBlock{})
	if err != nil {
		t.Fatalf("generate: %v", err)
	}
	var reflected map[string]any
	if err := json.Unmarshal(raw, &reflected); err != nil {
		t.Fatalf("generated schema must be valid JSON: %v", err)
	}
	if reflected["$schema"] != config.Draft2020 {
		t.Fatalf("generated schema must declare draft 2020-12: %v", reflected["$schema"])
	}
	if !strings.Contains(string(raw), "landscape") {
		t.Fatalf("generated schema must include the app fields: %s", raw)
	}
}

func TestFragmentFromTypeProducesMountableFragment(t *testing.T) {
	t.Parallel()
	fragment, err := config.FragmentFromType(config.AppBlock{})
	if err != nil {
		t.Fatalf("fragment: %v", err)
	}
	if fragment["type"] != "object" {
		t.Fatalf("fragment must be an object schema: %v", fragment)
	}
	block := config.NewBlock("app", true, fragment)
	if block.Key != "app" || !block.Required {
		t.Fatalf("block wrong: %+v", block)
	}
}

func TestSchemaFromJSONRoundTrips(t *testing.T) {
	t.Parallel()
	raw, err := config.ComposeSchema(config.AppBlockSchema()).Marshal()
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	schema, err := config.SchemaFromJSON(raw)
	if err != nil {
		t.Fatalf("from json: %v", err)
	}
	if schema.Root()["type"] != "object" {
		t.Fatalf("round trip lost type: %v", schema.Root())
	}
}

func TestSchemaFromJSONRejectsInvalidJSON(t *testing.T) {
	t.Parallel()
	if _, err := config.SchemaFromJSON([]byte("{not json")); err == nil {
		t.Fatal("invalid JSON must be rejected")
	}
}

func TestSchemaMarshalRoundTrips(t *testing.T) {
	t.Parallel()
	raw, err := testhelper.Schema().Marshal()
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	var round map[string]any
	if err := json.Unmarshal(raw, &round); err != nil {
		t.Fatalf("marshalled schema must be valid JSON: %v", err)
	}
	if round["$schema"] != config.Draft2020 {
		t.Fatalf("marshalled schema lost its draft: %v", round)
	}
}
