package testhelper_test

import (
	"context"
	"fmt"
	"testing"

	"github.com/AtomiCloud/diene.go-standard-config/lib/standardconfig"
	"github.com/AtomiCloud/diene.go-standard-config/testhelper"
)

// ExampleFakePostgres builds a container-free postgres block for a unit tier.
func ExampleFakePostgres() {
	block := testhelper.FakePostgres("REPLICA")
	fmt.Println(standardconfig.Keys(block), block["REPLICA"].Port, block["REPLICA"].Password == "")
	// Output: [REPLICA] 5432 true
}

// ExampleFakeCache defaults the connection name when none is given.
func ExampleFakeCache() {
	block := testhelper.FakeCache("")
	fmt.Println(standardconfig.Keys(block), block[testhelper.DefaultKey].Host)
	// Output: [MAIN] cache.invalid
}

// ExampleFakeKv addresses a different endpoint from the cache fake, so wiring
// one where the other belongs fails on the address instead of passing quietly.
func ExampleFakeKv() {
	fmt.Println(testhelper.FakeKv("MAIN")["MAIN"].Host != testhelper.FakeCache("MAIN")["MAIN"].Host)
	// Output: true
}

// ExampleFakeStorage builds a container-free storage block with blank
// credentials, exactly as the committed YAML carries them.
func ExampleFakeStorage() {
	block := testhelper.FakeStorage("ASSETS")
	fmt.Println(block["ASSETS"].Bucket, block["ASSETS"].AccessKeyID == "")
	// Output: app true
}

// ExampleRequireUppercaseKeys asserts the authoring contract on a block as
// written.
func ExampleRequireUppercaseKeys() {
	testhelper.RequireUppercaseKeys(&testing.T{}, testhelper.FakePostgres("READ_REPLICA"))
	fmt.Println("uppercase")
	// Output: uppercase
}

// ExampleRequireConnectionNames asserts the contract that survives loading: a
// decoded block's connection names must be identifiers.
func ExampleRequireConnectionNames() {
	decoded := standardconfig.CacheBlock{"main": {Host: "cache.lapras.invalid"}}
	testhelper.RequireConnectionNames(&testing.T{}, decoded)
	fmt.Println("reachable")
	// Output: reachable
}

// ExampleRequireEntry resolves one connection out of a block, failing the test
// when it is absent.
func ExampleRequireEntry() {
	entry := testhelper.RequireEntry(&testing.T{}, testhelper.FakeStorage("ASSETS"), "ASSETS")
	fmt.Println(entry.Region)
	// Output: us-east-1
}

// ExampleRequireStarted is the one-line form a consumer's integration test uses.
func ExampleRequireStarted() {
	ctx := context.Background()

	postgres, err := testhelper.StartPostgres(ctx, testhelper.PostgresOptions{
		// A real test omits Runtime and gets a real container.
		Runtime: exampleRuntimeAt("127.0.0.1", 49153),
	})
	started := testhelper.RequireStarted(&testing.T{}, postgres, err)
	defer func() { _ = started.Terminate(ctx) }()

	// started.Block is a keyed postgres block valid against the preset schema,
	// ready to compose into a test configuration document.
	fmt.Println(started.Key, started.Entry.Database, started.Entry.Port)
	// Output: MAIN app 49153
}

// ExampleStartCache boots an ephemeral cache container and emits the matching
// cache block.
func ExampleStartCache() {
	ctx := context.Background()
	started, err := testhelper.StartCache(ctx, testhelper.RedisOptions{
		Key: "SESSION", Runtime: exampleRuntimeAt("127.0.0.1", 49154),
	})
	if err != nil {
		panic(err)
	}
	defer func() { _ = started.Terminate(ctx) }()
	fmt.Println(started.Key, started.Block[started.Key].Port)
	// Output: SESSION 49154
}

// ExampleStartKv boots a persistent kv container — a SEPARATE instance from any
// cache, because the durability contract differs.
func ExampleStartKv() {
	ctx := context.Background()
	started, err := testhelper.StartKv(ctx, testhelper.RedisOptions{
		DB: 1, Runtime: exampleRuntimeAt("127.0.0.1", 49155),
	})
	if err != nil {
		panic(err)
	}
	defer func() { _ = started.Terminate(ctx) }()
	fmt.Println(started.Key, started.Entry.DB)
	// Output: MAIN 1
}

// ExampleStartStorage boots an S3-compatible container with its bucket already
// created, because MinIO does not create one on boot.
func ExampleStartStorage() {
	ctx := context.Background()
	host, port, stop := exampleS3()
	defer stop()

	started, err := testhelper.StartStorage(ctx, testhelper.StorageOptions{
		Bucket: "assets", Runtime: exampleRuntimeAt(host, port),
	})
	if err != nil {
		panic(err)
	}
	defer func() { _ = started.Terminate(ctx) }()
	fmt.Println(started.Entry.Bucket, started.Entry.Region, started.Entry.ForcePathStyle)
	// Output: assets us-east-1 true
}

// ExampleCreateBucket adds a second bucket to an endpoint a start helper
// already returned.
func ExampleCreateBucket() {
	ctx := context.Background()
	host, port, stop := exampleS3()
	defer stop()

	started, err := testhelper.StartStorage(ctx, testhelper.StorageOptions{
		Runtime: exampleRuntimeAt(host, port),
	})
	if err != nil {
		panic(err)
	}
	defer func() { _ = started.Terminate(ctx) }()

	second := started.Entry
	second.Bucket = "thumbnails"
	fmt.Println(testhelper.CreateBucket(ctx, second))
	// Output: <nil>
}

// ExampleDockerRuntime is the default container runtime. A test substitutes its
// own [testhelper.Runtime] to drive the glue's failure paths without Docker.
func ExampleDockerRuntime() {
	options := testhelper.RedisOptions{Runtime: testhelper.DockerRuntime{}}
	fmt.Println(options.Runtime != nil)
	// Output: true
}
