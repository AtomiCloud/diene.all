package testhelper_test

import (
	"strings"
	"testing"

	"github.com/AtomiCloud/diene.go-standard-config/lib/standardconfig"
	"github.com/AtomiCloud/diene.go-standard-config/testhelper"
)

// The fakes exist so a unit tier can hold a real config block without a
// container. They are only worth shipping if what they emit is what the preset
// schema accepts, so that is what this suite proves.

func TestEveryFakeEmitsABlockValidAgainstItsOwnPresetSchema(t *testing.T) {
	requireBlockValid(t, standardconfig.PostgresBlockKey, testhelper.FakePostgres("MAIN"))
	requireBlockValid(t, standardconfig.CacheBlockKey, testhelper.FakeCache("MAIN"))
	requireBlockValid(t, standardconfig.KvBlockKey, testhelper.FakeKv("MAIN"))
	requireBlockValid(t, standardconfig.StorageBlockKey, testhelper.FakeStorage("ASSETS"))
}

func TestEveryFakeDefaultsItsConnectionName(t *testing.T) {
	for name, keys := range map[string][]string{
		"postgres": standardconfig.Keys(testhelper.FakePostgres("")),
		"cache":    standardconfig.Keys(testhelper.FakeCache("")),
		"kv":       standardconfig.Keys(testhelper.FakeKv("")),
		"storage":  standardconfig.Keys(testhelper.FakeStorage("")),
	} {
		if strings.Join(keys, ",") != testhelper.DefaultKey {
			t.Fatalf("%s fake keys = %v, want [%s]", name, keys, testhelper.DefaultKey)
		}
	}
}

func TestEveryFakeHonoursTheRequestedConnectionName(t *testing.T) {
	if _, found := testhelper.FakePostgres("REPLICA")["REPLICA"]; !found {
		t.Fatalf("%s", "FakePostgres() ignored the requested connection name")
	}
	if _, found := testhelper.FakeCache("SESSION")["SESSION"]; !found {
		t.Fatalf("%s", "FakeCache() ignored the requested connection name")
	}
	if _, found := testhelper.FakeKv("TOKENS")["TOKENS"]; !found {
		t.Fatalf("%s", "FakeKv() ignored the requested connection name")
	}
	if _, found := testhelper.FakeStorage("UPLOADS")["UPLOADS"]; !found {
		t.Fatalf("%s", "FakeStorage() ignored the requested connection name")
	}
}

func TestEveryFakeLeavesItsSecretsBlank(t *testing.T) {
	if testhelper.FakePostgres("")[testhelper.DefaultKey].Password != "" {
		t.Fatalf("%s", "FakePostgres() carries a password; secrets are blank in YAML (R14/M33)")
	}
	if testhelper.FakeCache("")[testhelper.DefaultKey].Password != "" {
		t.Fatalf("%s", "FakeCache() carries a password")
	}
	if testhelper.FakeKv("")[testhelper.DefaultKey].Password != "" {
		t.Fatalf("%s", "FakeKv() carries a password")
	}
	assets := testhelper.FakeStorage("")[testhelper.DefaultKey]
	if assets.AccessKeyID != "" || assets.SecretAccessKey != "" {
		t.Fatalf("FakeStorage() carries credentials: %+v", assets)
	}
}

func TestCacheAndKvFakesAddressDifferentInstances(t *testing.T) {
	cache := testhelper.FakeCache("")[testhelper.DefaultKey]
	kv := testhelper.FakeKv("")[testhelper.DefaultKey]
	if cache.Host == kv.Host {
		t.Fatalf("cache and kv fakes share host %q; they stand for separate instances", cache.Host)
	}
}
