package standardconfig_test

import (
	"strings"
	"testing"

	"github.com/AtomiCloud/diene.go-standard-config/lib/standardconfig"
)

func TestEveryPresetIsAKeyedMapWithNoKeySpellingConstraint(t *testing.T) {
	for name, preset := range standardconfig.Schemas() {
		if preset["type"] != "object" {
			t.Fatalf("%s preset type = %v, want object", name, preset["type"])
		}
		if _, present := preset["patternProperties"]; present {
			t.Fatalf("%s constrains key spelling with patternProperties; "+
				"the config lib rejects that as an authoring fault", name)
		}
		if _, present := preset["propertyNames"]; present {
			t.Fatalf("%s constrains key spelling with propertyNames; "+
				"the config lib rejects that as an authoring fault", name)
		}
		if _, present := preset["properties"]; present {
			t.Fatalf("%s declares fixed properties; a preset is a keyed map so a "+
				"second instance is YAML, not a schema change", name)
		}
		description := descriptionOf(t, preset)
		if !strings.Contains(description, "UPPERCASE") {
			t.Fatalf("%s block description does not state the UPPERCASE contract: %q", name, description)
		}
	}
}

func TestPortsAreConstrainedToTheValidRange(t *testing.T) {
	for _, name := range []string{
		standardconfig.PostgresBlockKey, standardconfig.CacheBlockKey, standardconfig.KvBlockKey,
	} {
		port, ok := entryProperties(t, standardconfig.Schemas()[name])["port"].(map[string]any)
		if !ok {
			t.Fatalf("%s declares no port", name)
		}
		if port["type"] != "integer" || port["minimum"] != 1 || port["maximum"] != 65535 {
			t.Fatalf("%s port schema = %v, want an integer in 1..65535", name, port)
		}
	}
}

func TestPostgresPoolSizingHasAFloorPerBound(t *testing.T) {
	pool, ok := entryProperties(t, standardconfig.PostgresSchema())["pool"].(map[string]any)
	if !ok {
		t.Fatalf("%s", "postgres declares no pool sizing")
	}
	properties := objectAt(t, pool, "properties")
	minimum := objectAt(t, properties, "min")
	maximum := objectAt(t, properties, "max")
	if minimum["minimum"] != 0 {
		t.Fatalf("pool.min floor = %v, want 0 (a pool may idle empty)", minimum["minimum"])
	}
	if maximum["minimum"] != 1 {
		t.Fatalf("pool.max floor = %v, want 1 (a pool of zero connections is not a pool)", maximum["minimum"])
	}
}

func TestNonSecretStringsRejectBlankValues(t *testing.T) {
	cases := map[string][]string{
		standardconfig.PostgresBlockKey: {"host", "database", "username"},
		standardconfig.CacheBlockKey:    {"host"},
		standardconfig.KvBlockKey:       {"host"},
		standardconfig.StorageBlockKey:  {"endpoint", "region", "bucket"},
	}
	for name, fields := range cases {
		properties := entryProperties(t, standardconfig.Schemas()[name])
		for _, field := range fields {
			declared, ok := properties[field].(map[string]any)
			if !ok {
				t.Fatalf("%s declares no %q", name, field)
			}
			if declared["minLength"] != 1 {
				t.Fatalf("%s.%s minLength = %v, want 1; a blank endpoint is a misconfiguration",
					name, field, declared["minLength"])
			}
		}
	}
}

func TestSecretDescriptionsNameTheInjectionContract(t *testing.T) {
	secrets := map[string][]string{
		standardconfig.PostgresBlockKey: {"password"},
		standardconfig.CacheBlockKey:    {"password"},
		standardconfig.KvBlockKey:       {"password"},
		standardconfig.StorageBlockKey:  {"accessKeyId", "secretAccessKey"},
	}
	for name, fields := range secrets {
		properties := entryProperties(t, standardconfig.Schemas()[name])
		for _, field := range fields {
			declared := objectAt(t, properties, field)
			description := descriptionOf(t, declared)
			if !strings.Contains(description, "blank in YAML") {
				t.Fatalf("%s.%s description = %q, want it to state the blank-in-YAML contract",
					name, field, description)
			}
		}
	}
}

func TestSchemasReturnsAnIndependentFragmentEachCall(t *testing.T) {
	first := standardconfig.PostgresSchema()
	first["type"] = "mutated"
	if standardconfig.PostgresSchema()["type"] != "object" {
		t.Fatalf("%s", "PostgresSchema() handed back shared state; a caller mutated the next caller's schema")
	}
	blocks := standardconfig.Schemas()
	delete(blocks, standardconfig.KvBlockKey)
	if len(standardconfig.Schemas()) != 4 {
		t.Fatalf("%s", "Schemas() handed back shared state")
	}
}

func TestSchemaForResolvesEveryShippedPreset(t *testing.T) {
	problems := newProblems(t, portal())
	for _, name := range standardconfig.PresetNames() {
		fragment, err := standardconfig.SchemaFor(problems, name)
		if err != nil {
			t.Fatalf("SchemaFor(%q) error = %v", name, err)
		}
		if fragment["type"] != "object" {
			t.Fatalf("SchemaFor(%q) = %v, want an object fragment", name, fragment)
		}
	}
}

func TestSchemaForRejectsAnUnshippedPreset(t *testing.T) {
	fragment, err := standardconfig.SchemaFor(newProblems(t, portal()), "queue")
	if err == nil {
		t.Fatalf("SchemaFor() invented a preset: %v", fragment)
	}
	if fragment != nil {
		t.Fatalf("SchemaFor() returned %v alongside an error; a nil fragment constrains nothing", fragment)
	}
	raised := requireProblem(t, err)
	if !strings.HasSuffix(raised.Type, standardconfig.ProblemPresetUnknown) {
		t.Fatalf("SchemaFor() problem type = %q", raised.Type)
	}
	shipped, ok := raised.Data["shipped"].([]string)
	if !ok || strings.Join(shipped, ",") != strings.Join(standardconfig.PresetNames(), ",") {
		t.Fatalf("SchemaFor() problem data shipped = %v, want the frozen set", raised.Data["shipped"])
	}
}

func TestSchemaForWithoutAProblemFactoryReportsTheMissingFactory(t *testing.T) {
	_, err := standardconfig.SchemaFor(nil, "queue")
	if err == nil {
		t.Fatalf("%s", "SchemaFor() with no problem factory returned no error")
	}
	if !strings.Contains(err.Error(), "no problem factory supplied") {
		t.Fatalf("SchemaFor() error = %q", err.Error())
	}
}
