package testhelper_test

import (
	"context"
	"net"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-standard-config/lib/standardconfig"
	"github.com/AtomiCloud/diene.go-standard-config/testhelper"
)

// The glue's whole claim is "this block addresses a real, ready dependency".
// The stub-runtime suite proves the block SHAPE; only a real container proves
// the claim, so these tests boot one per preset and dial the address the block
// carries.

// requireDialable fails the test unless something accepts a TCP connection at
// the emitted address.
func requireDialable(t *testing.T, host string, port int) {
	t.Helper()
	address := net.JoinHostPort(host, strconv.Itoa(port))
	dialer := net.Dialer{Timeout: 15 * time.Second}
	conn, err := dialer.DialContext(context.Background(), "tcp", address)
	if err != nil {
		t.Fatalf("the emitted block points at %s, which does not accept connections: %v", address, err)
	}
	if err := conn.Close(); err != nil {
		t.Fatalf("close %s: %v", address, err)
	}
}

func TestStartPostgresBootsAReachablePostgres(t *testing.T) {
	ctx := context.Background()
	postgres, err := testhelper.StartPostgres(ctx, testhelper.PostgresOptions{Key: "MAIN"})
	started := testhelper.RequireStarted(t, postgres, err)
	t.Cleanup(func() {
		if err := started.Terminate(ctx); err != nil {
			t.Errorf("terminate postgres: %v", err)
		}
	})
	requireBlockValid(t, standardconfig.PostgresBlockKey, started.Block)
	testhelper.RequireUppercaseKeys(t, started.Block)
	entry := testhelper.RequireEntry(t, started.Block, "MAIN")
	requireDialable(t, entry.Host, entry.Port)
}

func TestStartCacheAndStartKvBootTwoReachableInstances(t *testing.T) {
	ctx := context.Background()
	cache, cacheErr := testhelper.StartCache(ctx, testhelper.RedisOptions{})
	startedCache := testhelper.RequireStarted(t, cache, cacheErr)
	t.Cleanup(func() {
		if err := startedCache.Terminate(ctx); err != nil {
			t.Errorf("terminate cache: %v", err)
		}
	})
	kv, kvErr := testhelper.StartKv(ctx, testhelper.RedisOptions{Key: "TOKENS"})
	startedKv := testhelper.RequireStarted(t, kv, kvErr)
	t.Cleanup(func() {
		if err := startedKv.Terminate(ctx); err != nil {
			t.Errorf("terminate kv: %v", err)
		}
	})

	requireBlockValid(t, standardconfig.CacheBlockKey, startedCache.Block)
	requireBlockValid(t, standardconfig.KvBlockKey, startedKv.Block)
	if startedCache.Entry.Port == startedKv.Entry.Port {
		t.Fatalf("%s", "cache and kv resolved the same container; durability semantics differ")
	}
	requireDialable(t, startedCache.Entry.Host, startedCache.Entry.Port)
	requireDialable(t, startedKv.Entry.Host, startedKv.Entry.Port)
}

func TestStartStorageBootsMinioWithItsBucketAlreadyCreated(t *testing.T) {
	ctx := context.Background()
	storage, err := testhelper.StartStorage(ctx, testhelper.StorageOptions{Key: "ASSETS", Bucket: "assets"})
	started := testhelper.RequireStarted(t, storage, err)
	t.Cleanup(func() {
		if err := started.Terminate(ctx); err != nil {
			t.Errorf("terminate storage: %v", err)
		}
	})
	requireBlockValid(t, standardconfig.StorageBlockKey, started.Block)
	if !strings.HasPrefix(started.Entry.Endpoint, "http://") {
		t.Fatalf("storage endpoint = %q, want an http endpoint", started.Entry.Endpoint)
	}
	if !started.Entry.ForcePathStyle {
		t.Fatalf("%s", "storage forcePathStyle = false; MinIO addresses buckets path-style")
	}

	// The bucket the helper created already exists, and CreateBucket is
	// idempotent enough to say so rather than fail. A second, different bucket
	// is the surface a consumer with several buckets actually uses.
	second := started.Entry
	second.Bucket = "thumbnails"
	if err := testhelper.CreateBucket(ctx, second); err != nil {
		t.Fatalf("CreateBucket() error = %v", err)
	}
}

func TestCreateBucketReportsARejectedRequest(t *testing.T) {
	ctx := context.Background()
	storage, err := testhelper.StartStorage(ctx, testhelper.StorageOptions{})
	started := testhelper.RequireStarted(t, storage, err)
	t.Cleanup(func() {
		if err := started.Terminate(ctx); err != nil {
			t.Errorf("terminate storage: %v", err)
		}
	})

	wrongSecret := started.Entry
	wrongSecret.Bucket = "rejected"
	wrongSecret.SecretAccessKey = "not-the-secret"
	if err := testhelper.CreateBucket(ctx, wrongSecret); err == nil {
		t.Fatalf("%s", "CreateBucket() accepted a request signed with the wrong secret")
	} else if !strings.Contains(err.Error(), "HTTP") {
		t.Fatalf("CreateBucket() error = %v, want the rejected status", err)
	}
}

func TestTheDockerRuntimeSurfacesAnUnknownPortAndAnUnknownImage(t *testing.T) {
	ctx := context.Background()
	cache, err := testhelper.StartCache(ctx, testhelper.RedisOptions{})
	started := testhelper.RequireStarted(t, cache, err)
	t.Cleanup(func() {
		if err := started.Terminate(ctx); err != nil {
			t.Errorf("terminate cache: %v", err)
		}
	})
	if _, err := started.Container.Port(ctx, "9999/tcp"); err == nil {
		t.Fatalf("%s", "Port() invented a mapping for a port the container never exposed")
	}
	if _, err := (testhelper.DockerRuntime{}).Start(ctx,
		newRequest("diene.invalid/does-not-exist:0")); err == nil {
		t.Fatalf("%s", "Start() started a container from an image that cannot exist")
	}
}
