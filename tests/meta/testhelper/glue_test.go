package testhelper_test

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/AtomiCloud/diene.go-standard-config/lib/standardconfig"
	"github.com/AtomiCloud/diene.go-standard-config/testhelper"
)

// These drive the container glue through the [testhelper.Runtime] seam, so
// every option default and every failure path is exercised deterministically
// and in milliseconds. The real-Docker half lives in containers_test.go.

func TestStartPostgresEmitsAKeyedSchemaValidBlock(t *testing.T) {
	runtime := okRuntime("127.0.0.1", 49153, nil)
	started, err := testhelper.StartPostgres(context.Background(), testhelper.PostgresOptions{Runtime: runtime})
	if err != nil {
		t.Fatalf("StartPostgres() error = %v", err)
	}
	if started.Key != testhelper.DefaultKey {
		t.Fatalf("StartPostgres() key = %q, want %q", started.Key, testhelper.DefaultKey)
	}
	if started.Entry.Host != "127.0.0.1" || started.Entry.Port != 49153 {
		t.Fatalf("StartPostgres() entry = %+v, want the published address", started.Entry)
	}
	if started.Entry.Database != "app" || started.Entry.Username != "app" ||
		started.Entry.Password != "app-secret" {
		t.Fatalf("StartPostgres() entry = %+v, want the documented defaults", started.Entry)
	}
	if started.Entry.SSL || started.Entry.Pool.Max != 10 {
		t.Fatalf("StartPostgres() entry = %+v", started.Entry)
	}
	testhelper.RequireUppercaseKeys(t, started.Block)
	requireBlockValid(t, standardconfig.PostgresBlockKey, started.Block)

	request := runtime.requests[0]
	if request.Image != testhelper.DefaultPostgresImage {
		t.Fatalf("image = %q, want %q", request.Image, testhelper.DefaultPostgresImage)
	}
	if request.Env["POSTGRES_DB"] != "app" || request.Env["POSTGRES_PASSWORD"] != "app-secret" {
		t.Fatalf("container env = %v, want the requested database and password", request.Env)
	}
}

func TestStartPostgresHonoursEveryOption(t *testing.T) {
	runtime := okRuntime("db.local", 6000, nil)
	started, err := testhelper.StartPostgres(context.Background(), testhelper.PostgresOptions{
		Key: "REPLICA", Image: "postgres:15-alpine",
		Database: "billing", Username: "billing_ro", Password: "hunter2", Runtime: runtime,
	})
	if err != nil {
		t.Fatalf("StartPostgres() error = %v", err)
	}
	if started.Key != "REPLICA" || started.Block["REPLICA"].Database != "billing" {
		t.Fatalf("StartPostgres() = %+v, want the requested connection", started)
	}
	if runtime.requests[0].Image != "postgres:15-alpine" {
		t.Fatalf("image = %q, want the override", runtime.requests[0].Image)
	}
}

func TestStartCacheAndStartKvEmitSeparateSchemaValidBlocks(t *testing.T) {
	cache, err := testhelper.StartCache(context.Background(), testhelper.RedisOptions{
		Runtime: okRuntime("127.0.0.1", 49154, nil),
	})
	if err != nil {
		t.Fatalf("StartCache() error = %v", err)
	}
	kv, err := testhelper.StartKv(context.Background(), testhelper.RedisOptions{
		Key: "TOKENS", DB: 3, Runtime: okRuntime("127.0.0.1", 49155, nil),
	})
	if err != nil {
		t.Fatalf("StartKv() error = %v", err)
	}
	requireBlockValid(t, standardconfig.CacheBlockKey, cache.Block)
	requireBlockValid(t, standardconfig.KvBlockKey, kv.Block)
	if cache.Entry.Port == kv.Entry.Port {
		t.Fatalf("%s", "cache and kv resolved one container; they must be separate instances")
	}
	if kv.Entry.DB != 3 || cache.Entry.DB != 0 {
		t.Fatalf("cache db = %d, kv db = %d, want the requested indexes", cache.Entry.DB, kv.Entry.DB)
	}
	if kv.Key != "TOKENS" || cache.Key != testhelper.DefaultKey {
		t.Fatalf("cache key = %q, kv key = %q", cache.Key, kv.Key)
	}
}

func TestStartCacheUsesTheDefaultRedisImageAndWaitStrategy(t *testing.T) {
	runtime := okRuntime("127.0.0.1", 49156, nil)
	if _, err := testhelper.StartCache(context.Background(),
		testhelper.RedisOptions{Runtime: runtime}); err != nil {
		t.Fatalf("StartCache() error = %v", err)
	}
	request := runtime.requests[0]
	if request.Image != testhelper.DefaultRedisImage {
		t.Fatalf("image = %q, want %q", request.Image, testhelper.DefaultRedisImage)
	}
	if request.WaitingFor == nil {
		t.Fatalf("%s", "the cache container has no wait strategy; the helper would return before it is ready")
	}
}

func TestStartKvHonoursTheImageOverride(t *testing.T) {
	runtime := okRuntime("127.0.0.1", 49157, nil)
	if _, err := testhelper.StartKv(context.Background(), testhelper.RedisOptions{
		Image: "valkey/valkey:8-alpine", Runtime: runtime,
	}); err != nil {
		t.Fatalf("StartKv() error = %v", err)
	}
	if runtime.requests[0].Image != "valkey/valkey:8-alpine" {
		t.Fatalf("image = %q, want the override", runtime.requests[0].Image)
	}
}

func TestEveryStartHelperSurfacesAStartFailure(t *testing.T) {
	ctx := context.Background()
	failing := func() *stubRuntime { return &stubRuntime{startErr: errStub} }

	if _, err := testhelper.StartPostgres(ctx,
		testhelper.PostgresOptions{Runtime: failing()}); !errors.Is(err, errStub) {
		t.Fatalf("StartPostgres() error = %v, want the runtime failure", err)
	}
	if _, err := testhelper.StartCache(ctx,
		testhelper.RedisOptions{Runtime: failing()}); !errors.Is(err, errStub) {
		t.Fatalf("StartCache() error = %v, want the runtime failure", err)
	}
	if _, err := testhelper.StartKv(ctx,
		testhelper.RedisOptions{Runtime: failing()}); !errors.Is(err, errStub) {
		t.Fatalf("StartKv() error = %v, want the runtime failure", err)
	}
	if _, err := testhelper.StartStorage(ctx,
		testhelper.StorageOptions{Runtime: failing()}); !errors.Is(err, errStub) {
		t.Fatalf("StartStorage() error = %v, want the runtime failure", err)
	}
}

func TestAnUnresolvableAddressStopsTheContainerItStarted(t *testing.T) {
	ctx := context.Background()
	terminations := 0
	hostFails := &stubRuntime{container: &stubContainer{hostErr: errStub, terminateSeen: &terminations}}
	if _, err := testhelper.StartPostgres(ctx,
		testhelper.PostgresOptions{Runtime: hostFails}); !errors.Is(err, errStub) {
		t.Fatalf("StartPostgres() error = %v, want the host failure", err)
	}
	if terminations != 1 {
		t.Fatalf("terminations = %d, want the started container stopped rather than leaked", terminations)
	}

	terminations = 0
	portFails := &stubRuntime{container: &stubContainer{
		host: "127.0.0.1", portErr: errStub, terminateSeen: &terminations,
	}}
	if _, err := testhelper.StartCache(ctx,
		testhelper.RedisOptions{Runtime: portFails}); !errors.Is(err, errStub) {
		t.Fatalf("StartCache() error = %v, want the port failure", err)
	}
	if terminations != 1 {
		t.Fatalf("terminations = %d, want the started container stopped rather than leaked", terminations)
	}
}

func TestACleanupFailureNeverHidesTheRealCause(t *testing.T) {
	failing := &stubRuntime{container: &stubContainer{
		hostErr: errStub, terminateErr: errors.New("cleanup also failed"),
	}}
	_, err := testhelper.StartKv(context.Background(), testhelper.RedisOptions{Runtime: failing})
	if !errors.Is(err, errStub) {
		t.Fatalf("StartKv() error = %v, want the original cause, not the cleanup failure", err)
	}
}

func TestTerminateDelegatesToTheContainerForEveryPreset(t *testing.T) {
	ctx := context.Background()
	terminations := 0

	postgres, err := testhelper.StartPostgres(ctx,
		testhelper.PostgresOptions{Runtime: okRuntime("h", 1, &terminations)})
	if err != nil {
		t.Fatalf("StartPostgres() error = %v", err)
	}
	cache, err := testhelper.StartCache(ctx,
		testhelper.RedisOptions{Runtime: okRuntime("h", 2, &terminations)})
	if err != nil {
		t.Fatalf("StartCache() error = %v", err)
	}
	kv, err := testhelper.StartKv(ctx, testhelper.RedisOptions{Runtime: okRuntime("h", 3, &terminations)})
	if err != nil {
		t.Fatalf("StartKv() error = %v", err)
	}

	for _, terminate := range []func(context.Context) error{
		postgres.Terminate, cache.Terminate, kv.Terminate,
	} {
		if err := terminate(ctx); err != nil {
			t.Fatalf("Terminate() error = %v", err)
		}
	}
	if terminations != 3 {
		t.Fatalf("terminations = %d, want one per started preset", terminations)
	}
}

func TestStorageStopsTheContainerWhenTheBucketCannotBeCreated(t *testing.T) {
	terminations := 0
	// Port 1 is not listening, so the bucket PUT fails at the transport layer.
	runtime := okRuntime("127.0.0.1", 1, &terminations)
	_, err := testhelper.StartStorage(context.Background(), testhelper.StorageOptions{Runtime: runtime})
	if err == nil {
		t.Fatalf("%s", "StartStorage() returned a block pointing at a bucket it never created")
	}
	if !strings.Contains(err.Error(), "create bucket") {
		t.Fatalf("StartStorage() error = %v, want the bucket failure", err)
	}
	if terminations != 1 {
		t.Fatalf("terminations = %d, want the started container stopped rather than leaked", terminations)
	}
}

func TestStorageRequestsTheDocumentedContainerShape(t *testing.T) {
	runtime := okRuntime("127.0.0.1", 1, nil)
	_, _ = testhelper.StartStorage(context.Background(), testhelper.StorageOptions{
		Image: "minio/minio:RELEASE.2024-01-01T00-00-00Z", AccessKeyID: "ak", SecretAccessKey: "sk",
		Runtime: runtime,
	})
	request := runtime.requests[0]
	if request.Image != "minio/minio:RELEASE.2024-01-01T00-00-00Z" {
		t.Fatalf("image = %q, want the override", request.Image)
	}
	if strings.Join(request.Cmd, " ") != "server /data" {
		t.Fatalf("cmd = %v, want the MinIO server command", request.Cmd)
	}
	if request.Env["MINIO_ROOT_USER"] != "ak" || request.Env["MINIO_ROOT_PASSWORD"] != "sk" {
		t.Fatalf("env = %v, want the requested credentials", request.Env)
	}
}

func TestTheDefaultRuntimeIsUsedWhenNoneIsSupplied(t *testing.T) {
	// No runtime and no Docker reachable in this call: the helper must still
	// reach the daemon rather than silently no-op, so an error is the pass
	// condition when Docker is absent and a started container when it is not.
	started, err := testhelper.StartCache(context.Background(), testhelper.RedisOptions{
		Image: "diene.invalid/does-not-exist:0",
	})
	if err == nil {
		_ = started.Terminate(context.Background())
		t.Fatalf("%s", "StartCache() started a container from an image that cannot exist")
	}
}

func TestCreateBucketRejectsAnUnusableEndpoint(t *testing.T) {
	err := testhelper.CreateBucket(context.Background(), standardconfig.StorageEntry{
		Endpoint: ":", Bucket: "assets", Region: "us-east-1",
	})
	if err == nil {
		t.Fatalf("%s", "CreateBucket() accepted an endpoint that is not a URL")
	}
	if !strings.Contains(err.Error(), "not usable") {
		t.Fatalf("CreateBucket() error = %v, want the unusable-endpoint report", err)
	}
}

func TestCreateBucketSurfacesATransportFailure(t *testing.T) {
	err := testhelper.CreateBucket(context.Background(), standardconfig.StorageEntry{
		Endpoint: "http://127.0.0.1:1", Bucket: "assets", Region: "us-east-1",
	})
	if err == nil {
		t.Fatalf("%s", "CreateBucket() reported success against a closed port")
	}
	if !strings.Contains(err.Error(), "create bucket") {
		t.Fatalf("CreateBucket() error = %v, want the transport failure", err)
	}
}
