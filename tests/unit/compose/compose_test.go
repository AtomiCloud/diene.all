package compose_test

import (
	"context"
	"strings"
	"testing"

	"github.com/AtomiCloud/diene.go-config/lib/config"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
	"github.com/AtomiCloud/diene.go-otel/lib/otel"
	"github.com/AtomiCloud/diene.go-standard-config/lib/standardconfig"
)

// load runs the real three-layer load and fails the test on error.
func load(t *testing.T, env map[string]string) *config.Config {
	t.Helper()
	loaded, err := loaderFor(t, baseDocument, overlayDocument, env).Load(context.Background())
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	return loaded
}

func TestComposedRootValidatesEveryBlockAtOnce(t *testing.T) {
	loaded := load(t, nil)
	app, err := loaded.App()
	if err != nil {
		t.Fatalf("App() error = %v", err)
	}
	if app.Landscape != "lapras" || app.Service != "billing" {
		t.Fatalf("App() = %+v, want the service-tree identity from the base layer", app)
	}
}

func TestOverlayFlipsInfraToItsLandscapePostureAndKeepsBaseDefaults(t *testing.T) {
	var block standardconfig.PostgresBlock
	if err := load(t, nil).Decode(standardconfig.PostgresBlockKey, &block); err != nil {
		t.Fatalf("Decode(postgres) error = %v", err)
	}
	main, err := standardconfig.Named(presetProblems(t), block, "MAIN")
	if err != nil {
		t.Fatalf("Named(MAIN) error = %v", err)
	}
	if main.Host != "primary.lapras.invalid" {
		t.Fatalf("postgres MAIN host = %q, want the overlay value", main.Host)
	}
	if !main.SSL {
		t.Fatalf("%s", "postgres MAIN ssl = false, want the overlay to have flipped it")
	}
	if main.Database != "billing" || main.Pool.Max != 10 {
		t.Fatalf("postgres MAIN = %+v, want the base defaults preserved under a sparse overlay", main)
	}
}

func TestKeyedMultiInstanceIsYAMLOnly(t *testing.T) {
	var block standardconfig.PostgresBlock
	if err := load(t, nil).Decode(standardconfig.PostgresBlockKey, &block); err != nil {
		t.Fatalf("Decode(postgres) error = %v", err)
	}
	// The loader canonicalizes key spelling, so the UPPERCASE names in both YAML
	// layers arrive lower-cased. That is exactly why lookups go through
	// standardconfig.Named rather than indexing the map directly.
	if got := standardconfig.Keys(block); strings.Join(got, ",") != "main,replica" {
		t.Fatalf("postgres connections = %v, want the overlay's second pool added by YAML alone", got)
	}
	replica, err := standardconfig.Named(presetProblems(t), block, "REPLICA")
	if err != nil {
		t.Fatalf("Named(REPLICA) error = %v", err)
	}
	if replica.Username != "billing_ro" || replica.Pool.Max != 4 {
		t.Fatalf("REPLICA = %+v, want the overlay-declared pool", replica)
	}
}

func TestEnvInjectsTheBlankYAMLSecretsLast(t *testing.T) {
	loaded := load(t, map[string]string{
		"ATOMI_POSTGRES__MAIN__PASSWORD":         "pg-secret",
		"ATOMI_CACHE__MAIN__PASSWORD":            "cache-secret",
		"ATOMI_KV__MAIN__PASSWORD":               "kv-secret",
		"ATOMI_STORAGE__ASSETS__ACCESSKEYID":     "ak",
		"ATOMI_STORAGE__ASSETS__SECRETACCESSKEY": "sk",
	})

	var postgres standardconfig.PostgresBlock
	if err := loaded.Decode(standardconfig.PostgresBlockKey, &postgres); err != nil {
		t.Fatalf("Decode(postgres) error = %v", err)
	}
	if named(t, postgres, "MAIN").Password != "pg-secret" {
		t.Fatalf("postgres password = %q, want the env-injected secret", named(t, postgres, "MAIN").Password)
	}

	var cache standardconfig.CacheBlock
	if err := loaded.Decode(standardconfig.CacheBlockKey, &cache); err != nil {
		t.Fatalf("Decode(cache) error = %v", err)
	}
	var kv standardconfig.KvBlock
	if err := loaded.Decode(standardconfig.KvBlockKey, &kv); err != nil {
		t.Fatalf("Decode(kv) error = %v", err)
	}
	if named(t, cache, "MAIN").Password == named(t, kv, "MAIN").Password {
		t.Fatalf("%s", "cache and kv resolved the same secret; they are separate instances")
	}
	if named(t, cache, "MAIN").Host != "dragonfly.lapras.invalid" || named(t, kv, "MAIN").Host != "upstash.lapras.invalid" {
		t.Fatalf("cache=%+v kv=%+v, want two distinct endpoints", named(t, cache, "MAIN"), named(t, kv, "MAIN"))
	}

	var storage standardconfig.StorageBlock
	if err := loaded.Decode(standardconfig.StorageBlockKey, &storage); err != nil {
		t.Fatalf("Decode(storage) error = %v", err)
	}
	assets := named(t, storage, "ASSETS")
	if assets.AccessKeyID != "ak" || assets.SecretAccessKey != "sk" {
		t.Fatalf("storage credentials = %+v, want both env-injected", assets)
	}
	if assets.ForcePathStyle {
		t.Fatalf("%s", "storage forcePathStyle = true, want the overlay's virtual-hosted posture")
	}
}

func TestBlankEnvValuesAreUnset(t *testing.T) {
	loaded := load(t, map[string]string{"ATOMI_POSTGRES__MAIN__HOST": ""})
	var block standardconfig.PostgresBlock
	if err := loaded.Decode(standardconfig.PostgresBlockKey, &block); err != nil {
		t.Fatalf("Decode(postgres) error = %v", err)
	}
	if named(t, block, "MAIN").Host != "primary.lapras.invalid" {
		t.Fatalf("postgres host = %q; a blank env value is unset (M33), not an override",
			named(t, block, "MAIN").Host)
	}
}

func TestTheOtelEngineBlockIsMergedByConfigNotByThisLibrary(t *testing.T) {
	loaded := load(t, nil)
	raw := loaded.Raw()
	if _, present := raw[otel.BlockKey]; !present {
		t.Fatalf("%s", "the otel block did not survive the merge")
	}
	for _, preset := range standardconfig.PresetNames() {
		if _, present := raw[preset]; !present {
			t.Fatalf("the %s preset did not survive the merge", preset)
		}
	}
	block := config.NewBlock(otel.BlockKey, false, otel.JSONSchema())
	if block.Key != otel.BlockKey {
		t.Fatalf("otel block key = %q, want %q", block.Key, otel.BlockKey)
	}
	if _, owned := standardconfig.Schemas()[otel.BlockKey]; owned {
		t.Fatalf("%s", "standard-config ships an otel block; engine blocks are engine-owned (C0 §3)")
	}
}

func TestAnInvalidInfraValueFailsFastOnTheMergedTree(t *testing.T) {
	broken := strings.Replace(overlayDocument,
		"    host: primary.lapras.invalid\n", "    host: primary.lapras.invalid\n    port: 70000\n", 1)
	_, err := loaderFor(t, baseDocument, broken, nil).Load(context.Background())
	if err == nil {
		t.Fatalf("%s", "Load() accepted a port outside the valid range")
	}
	issues, ok := config.ValidationIssues(err)
	if !ok {
		t.Fatalf("Load() error = %v, want a problem-typed validation failure", err)
	}
	if len(issues) == 0 {
		t.Fatalf("%s", "validation failed with no reported issue")
	}
}

func TestAnUnknownInfraKeyIsRejected(t *testing.T) {
	broken := strings.Replace(baseDocument,
		"    database: billing\n", "    database: billing\n    databse: typo\n", 1)
	_, err := loaderFor(t, broken, overlayDocument, nil).Load(context.Background())
	if err == nil {
		t.Fatalf("%s", "Load() accepted a misspelled infra key; the entry schemas are closed")
	}
}

func TestTheKeyContractIsEnforcedInGoBecauseTheSchemaCannot(t *testing.T) {
	unreachable := strings.Replace(baseDocument, "cache:\n  MAIN:", "cache:\n  RATE-LIMIT:", 1)
	unreachable = strings.Replace(unreachable, "cache:\n  MAIN:\n    host: dragonfly", "", 1)
	overlay := strings.Replace(overlayDocument,
		"cache:\n  MAIN:\n    host: dragonfly.lapras.invalid\n    tls: true\n", "", 1)
	loaded, err := loaderFor(t, unreachable, overlay, nil).Load(context.Background())
	if err != nil {
		t.Fatalf("Load() error = %v; the schema cannot constrain key spelling, so this must pass", err)
	}
	var block standardconfig.CacheBlock
	if err := loaded.Decode(standardconfig.CacheBlockKey, &block); err != nil {
		t.Fatalf("Decode(cache) error = %v", err)
	}
	if err := standardconfig.ValidateKeys(
		presetProblems(t), standardconfig.CacheBlockKey, block,
	); err == nil {
		t.Fatalf("ValidateKeys() accepted %v, a name with no environment override path",
			standardconfig.Keys(block))
	}
}

// named resolves a connection through the canonical lookup, failing the test
// rather than returning an error the caller has to re-check.
func named[E any](t *testing.T, block map[string]E, name string) E {
	t.Helper()
	entry, err := standardconfig.Named(presetProblems(t), block, name)
	if err != nil {
		t.Fatalf("Named(%q) error = %v", name, err)
	}
	return entry
}

// presetProblems builds this library's problem factory over the loaded
// service-tree identity, which is where a real service sources its portal.
func presetProblems(t *testing.T) *standardconfig.Problems {
	t.Helper()
	problems, err := standardconfig.NewProblems(problem.ErrorPortal{
		Scheme:    "https",
		Host:      "docs.atomi.cloud",
		Landscape: "lapras",
		Platform:  "sulfoxide",
		Service:   "billing",
		Module:    "core",
	})
	if err != nil {
		t.Fatalf("NewProblems() error = %v", err)
	}
	return problems
}
