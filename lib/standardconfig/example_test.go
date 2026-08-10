package standardconfig_test

import (
	"errors"
	"fmt"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
	"github.com/AtomiCloud/diene.go-standard-config/lib/standardconfig"
)

// examplePortal is the service-tree error portal the examples mint problem type
// URIs from. A real service passes its own build-time portal.
func examplePortal() problem.ErrorPortal {
	return problem.ErrorPortal{
		Scheme:    "https",
		Host:      "docs.atomi.cloud",
		Landscape: "lapras",
		Platform:  "sulfoxide",
		Service:   "billing",
		Module:    "core",
	}
}

// exampleProblems builds the problem factory the examples raise through.
func exampleProblems() *standardconfig.Problems {
	problems, err := standardconfig.NewProblems(examplePortal())
	if err != nil {
		panic(err)
	}
	return problems
}

// ExamplePostgresSchema mounts the postgres preset into a service's root
// schema. The fragment is a plain JSON Schema map, so it composes with the
// config library without this package depending on it.
func ExamplePostgresSchema() {
	schema := standardconfig.PostgresSchema()
	fmt.Println(schema["type"], mustObject(schema, "additionalProperties")["additionalProperties"])
	// Output: object false
}

// ExampleCacheSchema shows the cache preset is a keyed map of Redis-protocol
// endpoints.
func ExampleCacheSchema() {
	fmt.Println(standardconfig.Keys(entryProperties(standardconfig.CacheSchema())))
	// Output: [db host password port tls]
}

// ExampleKvSchema shows kv carries the same connection fields as cache while
// staying a separate block: the durability contract differs, not the protocol.
func ExampleKvSchema() {
	cacheProperties := entryProperties(standardconfig.CacheSchema())
	kvProperties := entryProperties(standardconfig.KvSchema())
	fmt.Println(standardconfig.KvBlockKey != standardconfig.CacheBlockKey,
		len(cacheProperties) == len(kvProperties))
	// Output: true true
}

// ExampleStorageSchema shows the S3-compatible storage preset's key set.
func ExampleStorageSchema() {
	fmt.Println(standardconfig.Keys(entryProperties(standardconfig.StorageSchema())))
	// Output: [accessKeyId bucket endpoint forcePathStyle region secretAccessKey]
}

// ExampleSchemas composes every shipped preset in one loop.
func ExampleSchemas() {
	for _, name := range standardconfig.PresetNames() {
		fragment := standardconfig.Schemas()[name]
		fmt.Println(name, fragment["type"])
	}
	// Output:
	// cache object
	// kv object
	// postgres object
	// storage object
}

// ExamplePresetNames lists the frozen infra presets.
func ExamplePresetNames() {
	fmt.Println(standardconfig.PresetNames())
	// Output: [cache kv postgres storage]
}

// ExampleSchemaFor resolves one preset fragment by its block key.
func ExampleSchemaFor() {
	fragment, err := standardconfig.SchemaFor(exampleProblems(), standardconfig.KvBlockKey)
	fmt.Println(err, fragment["type"])
	// Output: <nil> object
}

// ExampleSchemaFor_unknown shows an unshipped preset key is a problem-typed
// error rather than a nil fragment that silently constrains nothing.
func ExampleSchemaFor_unknown() {
	_, err := standardconfig.SchemaFor(exampleProblems(), "queue")
	var raised *problem.Error
	fmt.Println(errors.As(err, &raised), raised.Problem.Status)
	// Output: true 500
}

// ExampleNamed resolves one connection out of a decoded block.
func ExampleNamed() {
	block := standardconfig.PostgresBlock{
		"MAIN":    {Host: "primary.invalid", Port: 5432},
		"REPLICA": {Host: "replica.invalid", Port: 5432},
	}
	entry, err := standardconfig.Named(exampleProblems(), block, "REPLICA")
	fmt.Println(err, entry.Host)
	// Output: <nil> replica.invalid
}

// ExampleNamed_unknown shows a mistyped connection name fails loudly, naming
// the connections that do exist.
func ExampleNamed_unknown() {
	block := standardconfig.CacheBlock{"MAIN": {Host: "cache.invalid", Port: 6379}}
	_, err := standardconfig.Named(exampleProblems(), block, "SESSION")
	var raised *problem.Error
	errors.As(err, &raised)
	fmt.Println(raised.Problem.Data["known"])
	// Output: [MAIN]
}

// ExampleKeys enumerates connection names in stable order, because Go map
// iteration is randomized.
func ExampleKeys() {
	block := standardconfig.StorageBlock{
		"UPLOADS": {Bucket: "uploads"},
		"ASSETS":  {Bucket: "assets"},
	}
	fmt.Println(standardconfig.Keys(block))
	// Output: [ASSETS UPLOADS]
}

// ExampleNamed_canonical shows why the lookup ignores case: names are AUTHORED
// in UPPERCASE, but the config library canonicalizes key spelling, so a decoded
// block is keyed in lower case.
func ExampleNamed_canonical() {
	decoded := standardconfig.KvBlock{"main": {Host: "kv.lapras.invalid"}}
	entry, err := standardconfig.Named(exampleProblems(), decoded, "MAIN")
	fmt.Println(err, entry.Host)
	// Output: <nil> kv.lapras.invalid
}

// ExampleValidKey checks the UPPERCASE AUTHORING contract (R14) against names
// as written.
func ExampleValidKey() {
	fmt.Println(standardconfig.ValidKey("MAIN"), standardconfig.ValidKey("READ_REPLICA"),
		standardconfig.ValidKey("main"))
	// Output: true true false
}

// ExampleValidConnectionName checks the half of the contract that survives
// loading: a connection name must be an identifier, or its environment override
// path is unreachable.
func ExampleValidConnectionName() {
	fmt.Println(standardconfig.ValidConnectionName("main"),
		standardconfig.ValidConnectionName("rate-limit"))
	// Output: true false
}

// ExampleValidateKeys rejects a decoded block whose connection names have no
// reachable environment override path. Schema validation cannot do this: the
// config library matches keys canonically and rejects key-spelling constraints
// outright.
func ExampleValidateKeys() {
	block := standardconfig.KvBlock{"main": {Host: "kv.invalid"}, "rate-limit": {Host: "kv.invalid"}}
	err := standardconfig.ValidateKeys(exampleProblems(), standardconfig.KvBlockKey, block)
	var raised *problem.Error
	errors.As(err, &raised)
	fmt.Println(raised.Problem.Data["invalid"])
	// Output: [rate-limit]
}

// ExampleUppercaseKeyPattern shows the published patterns a consumer can reuse.
func ExampleUppercaseKeyPattern() {
	fmt.Println(standardconfig.UppercaseKeyPattern, standardconfig.ConnectionNamePattern)
	// Output: ^[A-Z][A-Z0-9_]*$ ^[A-Za-z][A-Za-z0-9_]*$
}

// ExampleNewProblems builds the problem factory bound to a service's own error
// portal, so a misconfigured connection is attributed to that service.
func ExampleNewProblems() {
	problems, err := standardconfig.NewProblems(examplePortal())
	fmt.Println(err, len(problems.Registry().Entries()))
	// Output: <nil> 4
}

// ExampleProblemTypes lists the shipped problem-type declarations a consumer
// registers into its own catalog.
func ExampleProblemTypes() {
	for _, declared := range standardconfig.ProblemTypes() {
		fmt.Println(declared.ID, declared.Status, declared.Version)
	}
	// Output:
	// connection-unknown 500 v1
	// connection-ambiguous 500 v1
	// connection-key-invalid 500 v1
	// preset-unknown 500 v1
}

// ExampleProblems_Raise mints one of the shipped problems as an RFC 9457
// envelope.
func ExampleProblems_Raise() {
	err := exampleProblems().Raise(standardconfig.ProblemConnectionUnknown, "no such pool", nil)
	var raised *problem.Error
	errors.As(err, &raised)
	fmt.Println(raised.Problem.Type)
	// Output: https://docs.atomi.cloud/docs/lapras/sulfoxide/billing/core/v1/connection-unknown
}

// ExampleProblems_Catalog renders the shipped problems as Problem CR content
// (C0 §14).
func ExampleProblems_Catalog() {
	catalog, err := exampleProblems().Catalog()
	fmt.Println(err, len(catalog.ToCRDContent()))
	// Output: <nil> 4
}

// ExampleProblems_Registry exposes the registry a consumer composes its own
// catalog from.
func ExampleProblems_Registry() {
	registry := exampleProblems().Registry()
	declared, found := registry.Lookup(standardconfig.ProblemPresetUnknown)
	fmt.Println(found, declared.Title)
	// Output: true Infra preset not shipped
}

// mustObject unwraps a nested object out of a schema fragment, panicking when
// it is absent. The examples read fragments to show their shape, so an absent
// key means the example itself is wrong.
func mustObject(source map[string]any, key string) map[string]any {
	nested, ok := source[key].(map[string]any)
	if !ok {
		panic("standardconfig example: no object schema at " + key)
	}
	return nested
}

// entryProperties unwraps a preset fragment's entry property map.
func entryProperties(preset map[string]any) map[string]any {
	return mustObject(mustObject(preset, "additionalProperties"), "properties")
}
