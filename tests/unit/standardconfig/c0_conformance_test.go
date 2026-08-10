package standardconfig_test

import (
	"encoding/json"
	"os"
	"slices"
	"strings"
	"testing"

	"github.com/AtomiCloud/diene.go-standard-config/lib/standardconfig"
)

// c0Presets is the transcribed C0 §3 oracle. It is data on disk, transcribed
// from the contract and the published bun sibling, so this suite compares the
// implementation against the CONTRACT rather than against itself.
type c0Presets struct {
	Presets map[string]struct {
		Keys    []string            `json:"keys"`
		Secrets []string            `json:"secrets"`
		Nested  map[string][]string `json:"nested"`
	} `json:"presets"`
}

// loadC0 reads the frozen preset oracle.
func loadC0(t *testing.T) c0Presets {
	t.Helper()
	raw, err := os.ReadFile("../../fixtures/c0/presets.json")
	if err != nil {
		t.Fatalf("read C0 preset fixture: %v", err)
	}
	var frozen c0Presets
	if err := json.Unmarshal(raw, &frozen); err != nil {
		t.Fatalf("decode C0 preset fixture: %v", err)
	}
	return frozen
}

func TestC0FreezesExactlyFourInfraPresets(t *testing.T) {
	frozen := loadC0(t)
	got := standardconfig.PresetNames()
	want := make([]string, 0, len(frozen.Presets))
	for name := range frozen.Presets {
		want = append(want, name)
	}
	slices.Sort(want)
	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Fatalf("PresetNames() = %v, want the C0-frozen set %v", got, want)
	}
	if len(standardconfig.Schemas()) != len(frozen.Presets) {
		t.Fatalf("Schemas() ships %d presets, C0 freezes %d", len(standardconfig.Schemas()), len(frozen.Presets))
	}
}

func TestC0PresetKeySetsMatchKeyForKey(t *testing.T) {
	frozen := loadC0(t)
	for name, want := range frozen.Presets {
		preset, found := standardconfig.Schemas()[name]
		if !found {
			t.Fatalf("C0 freezes preset %q but this library ships none", name)
		}
		properties := entryProperties(t, preset)
		gotKeys := standardconfig.Keys(properties)
		wantKeys := slices.Clone(want.Keys)
		slices.Sort(wantKeys)
		if strings.Join(gotKeys, ",") != strings.Join(wantKeys, ",") {
			t.Fatalf("%s entry keys = %v, C0 freezes %v", name, gotKeys, wantKeys)
		}
		for nested, nestedKeys := range want.Nested {
			sub, ok := properties[nested].(map[string]any)
			if !ok {
				t.Fatalf("%s.%s is not an object schema", name, nested)
			}
			subProperties, ok := sub["properties"].(map[string]any)
			if !ok {
				t.Fatalf("%s.%s declares no properties", name, nested)
			}
			gotNested := standardconfig.Keys(subProperties)
			sorted := slices.Clone(nestedKeys)
			slices.Sort(sorted)
			if strings.Join(gotNested, ",") != strings.Join(sorted, ",") {
				t.Fatalf("%s.%s keys = %v, C0 freezes %v", name, nested, gotNested, sorted)
			}
		}
	}
}

func TestC0PresetEntriesAreClosedAndFullyRequired(t *testing.T) {
	frozen := loadC0(t)
	for name := range frozen.Presets {
		entry := entrySchema(t, standardconfig.Schemas()[name])
		if closed, ok := entry["additionalProperties"].(bool); !ok || closed {
			t.Fatalf("%s entry accepts unknown keys; a misspelled infra key must fail validation", name)
		}
		required, ok := entry["required"].([]any)
		if !ok {
			t.Fatalf("%s entry declares no required list", name)
		}
		properties := entryProperties(t, standardconfig.Schemas()[name])
		if len(required) != len(properties) {
			t.Fatalf("%s requires %d of %d keys; every infra key is mandatory",
				name, len(required), len(properties))
		}
	}
}

func TestC0SecretsAreBlankableInYAML(t *testing.T) {
	frozen := loadC0(t)
	for name, want := range frozen.Presets {
		properties := entryProperties(t, standardconfig.Schemas()[name])
		for _, secret := range want.Secrets {
			field, ok := properties[secret].(map[string]any)
			if !ok {
				t.Fatalf("%s declares no %q key", name, secret)
			}
			if field["type"] != "string" {
				t.Fatalf("%s.%s type = %v, want string", name, secret, field["type"])
			}
			if _, constrained := field["minLength"]; constrained {
				t.Fatalf("%s.%s carries a minLength; secrets are blank in YAML (R14/M33)", name, secret)
			}
		}
	}
}

func TestCacheAndKvAreSeparateBlocksWithOneConnectionShape(t *testing.T) {
	if standardconfig.CacheBlockKey == standardconfig.KvBlockKey {
		t.Fatalf("%s", "cache and kv share a block key; a cache may never be relabelled as kv")
	}
	cache := entryProperties(t, standardconfig.CacheSchema())
	kv := entryProperties(t, standardconfig.KvSchema())
	if strings.Join(standardconfig.Keys(cache), ",") != strings.Join(standardconfig.Keys(kv), ",") {
		t.Fatalf("cache keys %v and kv keys %v diverged; both speak the Redis protocol",
			standardconfig.Keys(cache), standardconfig.Keys(kv))
	}
	cacheDescription := descriptionOf(t, standardconfig.CacheSchema())
	kvDescription := descriptionOf(t, standardconfig.KvSchema())
	if !strings.Contains(cacheDescription, "ephemeral") {
		t.Fatalf("cache block description does not state its ephemeral contract: %q", cacheDescription)
	}
	if !strings.Contains(kvDescription, "persistent") {
		t.Fatalf("kv block description does not state its persistent contract: %q", kvDescription)
	}
}

func TestBlockKeysAreTheFrozenRootNames(t *testing.T) {
	got := map[string]string{
		"postgres": standardconfig.PostgresBlockKey,
		"cache":    standardconfig.CacheBlockKey,
		"kv":       standardconfig.KvBlockKey,
		"storage":  standardconfig.StorageBlockKey,
	}
	for want, actual := range got {
		if actual != want {
			t.Fatalf("block key for %s = %q, want %q", want, actual, want)
		}
	}
}
