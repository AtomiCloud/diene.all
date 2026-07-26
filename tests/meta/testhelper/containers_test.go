package testhelper_test

import (
	"context"
	"errors"
	"net"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-e2e/testhelper"
	"github.com/AtomiCloud/diene.go-standard-config/lib/standardconfig"
)

// The stack glue is proven two ways. A FAKE runtime proves the wiring — the
// selection, the emitted blocks, and above all the unwind, which must never
// leave a container running when a later preset fails. Real Docker then proves
// the blocks address something that actually exists, which a fake cannot.
//
// Neither half boots telemetry infrastructure. This is the DB-adapter
// integration tier (G1): there is no fake OTLP collector here, and real export
// is a SIT concern against the Garden preview environment.

func TestStartStackRefusesToBootNothing(t *testing.T) {
	t.Parallel()

	_, err := testhelper.StartStack(context.Background(), testhelper.StackOptions{})
	if !errors.Is(err, testhelper.ErrEmptyStack) {
		t.Fatalf("StartStack() error = %v, want ErrEmptyStack", err)
	}
}

func TestStartStackEmitsABlockPerSelectedPreset(t *testing.T) {
	t.Parallel()

	runtime := &fakeRuntime{}
	stack, err := testhelper.StartStack(context.Background(), testhelper.StackOptions{
		Postgres: true, Cache: true, Kv: true, Runtime: runtime,
	})
	if err != nil {
		t.Fatalf("StartStack() error = %v", err)
	}
	if runtime.started != 3 {
		t.Fatalf("started %d containers, want exactly the three selected", runtime.started)
	}
	blocks := stack.Blocks()
	for _, key := range []string{standardconfig.PostgresBlockKey, standardconfig.CacheBlockKey, standardconfig.KvBlockKey} {
		if _, found := blocks[key]; !found {
			t.Fatalf("blocks = %v, want %q emitted", blocks, key)
		}
	}
	if _, found := blocks[standardconfig.StorageBlockKey]; found {
		t.Fatalf("blocks = %v, want no storage block for an unselected preset", blocks)
	}
	entry := testhelper.PresetRequireEntry(t, stack.Postgres.Block, testhelper.PresetDefaultKey)
	if entry.Host != "127.0.0.1" || entry.Port != 15432 {
		t.Fatalf("postgres entry = %+v, want the started container's address", entry)
	}
	if err := stack.Terminate(context.Background()); err != nil {
		t.Fatalf("Terminate() error = %v", err)
	}
	if stack.Postgres != nil || stack.Cache != nil || stack.Kv != nil {
		t.Fatalf("stack = %+v, want every handle released after teardown", stack)
	}
}

func TestStartStackHonoursAnExplicitKey(t *testing.T) {
	t.Parallel()

	stack, err := testhelper.StartStack(context.Background(), testhelper.StackOptions{
		Key: "REPORTS", Kv: true, Runtime: &fakeRuntime{},
	})
	if err != nil {
		t.Fatalf("StartStack() error = %v", err)
	}
	defer func() { _ = stack.Terminate(context.Background()) }()
	if _, found := stack.Kv.Block["REPORTS"]; !found {
		t.Fatalf("kv block = %v, want it keyed REPORTS", stack.Kv.Block)
	}
}

func TestStartStackUnwindsEveryPresetItAlreadyStarted(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name      string
		options   testhelper.StackOptions
		failAt    int
		wantTorn  int
		wantStart int
	}{
		{"postgres first", testhelper.StackOptions{Postgres: true, Cache: true}, 0, 0, 1},
		{"cache second", testhelper.StackOptions{Postgres: true, Cache: true}, 1, 1, 2},
		{"kv third", testhelper.StackOptions{Postgres: true, Cache: true, Kv: true}, 2, 2, 3},
		{"storage last", testhelper.StackOptions{Postgres: true, Cache: true, Kv: true, Storage: true}, 3, 3, 4},
	}
	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			t.Parallel()
			torn := 0
			failures := make([]error, testCase.failAt+1)
			failures[testCase.failAt] = errBoom
			containers := make([]testhelper.PresetContainer, testCase.failAt+1)
			for index := range containers {
				containers[index] = &fakeContainer{host: "127.0.0.1", port: 15432, terminateAt: &torn}
			}
			runtime := &fakeRuntime{containers: containers, failures: failures}
			options := testCase.options
			options.Runtime = runtime

			stack, err := testhelper.StartStack(context.Background(), options)
			if !errors.Is(err, errBoom) {
				t.Fatalf("StartStack() error = %v, want the boot failure", err)
			}
			if stack != nil {
				t.Fatalf("StartStack() = %+v, want no stack handed back", stack)
			}
			if runtime.started != testCase.wantStart {
				t.Fatalf("started %d containers, want %d", runtime.started, testCase.wantStart)
			}
			if torn != testCase.wantTorn {
				t.Fatalf("terminated %d containers, want the %d already started", torn, testCase.wantTorn)
			}
		})
	}
}

func TestTerminateReportsTheFirstTeardownFailureAndStillStopsTheRest(t *testing.T) {
	t.Parallel()

	torn := 0
	runtime := &fakeRuntime{containers: []testhelper.PresetContainer{
		&fakeContainer{host: "127.0.0.1", port: 15432, terminateAt: &torn},
		&fakeContainer{host: "127.0.0.1", port: 16379, terminateAt: &torn, terminateErr: errBoom},
	}}
	stack, err := testhelper.StartStack(context.Background(), testhelper.StackOptions{
		Postgres: true, Cache: true, Runtime: runtime,
	})
	if err != nil {
		t.Fatalf("StartStack() error = %v", err)
	}
	if err := stack.Terminate(context.Background()); !errors.Is(err, errBoom) {
		t.Fatalf("Terminate() error = %v, want the teardown failure reported", err)
	}
	if torn != 2 {
		t.Fatalf("terminated %d containers, want both attempted despite the failure", torn)
	}
}

func TestStartStackKeepsTheBootFailureAheadOfATeardownFailure(t *testing.T) {
	t.Parallel()

	torn := 0
	bootFailure := errors.New("boot refused")
	runtime := &fakeRuntime{
		containers: []testhelper.PresetContainer{
			&fakeContainer{host: "127.0.0.1", port: 15432, terminateAt: &torn, terminateErr: errBoom},
		},
		failures: []error{nil, bootFailure},
	}
	_, err := testhelper.StartStack(context.Background(), testhelper.StackOptions{
		Postgres: true, Cache: true, Runtime: runtime,
	})
	if !errors.Is(err, bootFailure) {
		t.Fatalf("StartStack() error = %v, want the boot failure rather than the teardown one", err)
	}
	if torn != 1 {
		t.Fatalf("terminated %d containers, want the started one cleaned up", torn)
	}
}

func TestRequireStackPassesAndFails(t *testing.T) {
	t.Parallel()

	good := &recorder{}
	stack, err := testhelper.StartStack(context.Background(), testhelper.StackOptions{
		Kv: true, Runtime: &fakeRuntime{},
	})
	if err != nil {
		t.Fatalf("StartStack() error = %v", err)
	}
	got := testhelper.RequireStack(good, stack, nil)
	expectPass(t, good)
	if got != stack {
		t.Fatalf("RequireStack() = %p, want the stack returned", got)
	}
	if err := got.Terminate(context.Background()); err != nil {
		t.Fatalf("Terminate() error = %v", err)
	}

	bad := &recorder{}
	testhelper.RequireStack(bad, nil, errBoom)
	expectFail(t, bad, "container stack did not start")
}

func TestPresetRequireStartedPassesAndFails(t *testing.T) {
	t.Parallel()

	stack, err := testhelper.StartStack(context.Background(), testhelper.StackOptions{
		Postgres: true, Runtime: &fakeRuntime{},
	})
	if err != nil {
		t.Fatalf("StartStack() error = %v", err)
	}
	defer func() { _ = stack.Terminate(context.Background()) }()

	good := &recorder{}
	started := testhelper.PresetRequireStarted(good, stack.Postgres, nil)
	expectPass(t, good)
	if started != stack.Postgres {
		t.Fatalf("PresetRequireStarted() = %p, want the started preset returned", started)
	}

	bad := &recorder{}
	testhelper.PresetRequireStarted[testhelper.PresetStartedPostgres](bad, nil, errBoom)
	if !bad.failed {
		t.Fatal("PresetRequireStarted() passed on a failed start")
	}
}

func TestPresetRequireEntryPassesAndFails(t *testing.T) {
	t.Parallel()

	block := testhelper.PresetFakePostgres(testhelper.PresetDefaultKey)

	good := &recorder{}
	entry := testhelper.PresetRequireEntry(good, block, testhelper.PresetDefaultKey)
	expectPass(t, good)
	if entry.Database == "" {
		t.Fatalf("entry = %+v, want the fake block's entry", entry)
	}

	bad := &recorder{}
	testhelper.PresetRequireEntry(bad, block, "ABSENT")
	if !bad.failed {
		t.Fatal("PresetRequireEntry() passed on a key the block does not carry")
	}
}

func TestStartStackBootsStorageAndEmitsItsBlock(t *testing.T) {
	t.Parallel()

	// The storage preset creates its bucket over the S3 API before returning, so
	// a fake container has to point at something that answers. A local HTTP stub
	// is enough and keeps the wiring proof hermetic; real MinIO is exercised in
	// the Docker-backed test below.
	host, port, stop := stubS3(t)
	defer stop()

	torn := 0
	runtime := &fakeRuntime{containers: []testhelper.PresetContainer{
		&fakeContainer{host: host, port: port, terminateAt: &torn},
	}}
	stack, err := testhelper.StartStack(context.Background(), testhelper.StackOptions{
		Storage: true, Runtime: runtime,
	})
	if err != nil {
		t.Fatalf("StartStack() error = %v", err)
	}
	blocks := stack.Blocks()
	if _, found := blocks[standardconfig.StorageBlockKey]; !found {
		t.Fatalf("blocks = %v, want the storage block emitted", blocks)
	}
	entry := testhelper.PresetRequireEntry(t, stack.Storage.Block, testhelper.PresetDefaultKey)
	if entry.Bucket == "" || entry.Endpoint == "" {
		t.Fatalf("storage entry = %+v, want the started container addressed", entry)
	}
	if !entry.ForcePathStyle {
		t.Fatalf("storage entry = %+v, want path-style addressing for a container endpoint", entry)
	}
	if err := stack.Terminate(context.Background()); err != nil {
		t.Fatalf("Terminate() error = %v", err)
	}
	if torn != 1 {
		t.Fatalf("terminated %d containers, want the storage container stopped", torn)
	}
}

// stubS3 answers the one bucket-creation request the storage preset makes.
func stubS3(t *testing.T) (string, int, func()) {
	t.Helper()
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, _ *http.Request) {
		writer.WriteHeader(http.StatusOK)
	}))
	address := strings.TrimPrefix(server.URL, "http://")
	host, rawPort, err := net.SplitHostPort(address)
	if err != nil {
		server.Close()
		t.Fatalf("SplitHostPort(%q) error = %v", address, err)
	}
	port, err := strconv.Atoi(rawPort)
	if err != nil {
		server.Close()
		t.Fatalf("Atoi(%q) error = %v", rawPort, err)
	}
	return host, port, server.Close
}

func TestStartStackAddressesLiveDependencies(t *testing.T) {
	t.Parallel()

	// The Docker-backed half. A fake runtime can prove the wiring but not that
	// the emitted block addresses anything, and "the port was mapped" is the one
	// claim a Testcontainers helper exists to make — so this boots the real
	// containers and connects to what the blocks name.
	//
	// Still no telemetry infrastructure: these are DATA dependencies only (G1).
	ctx := t.Context()
	stack, err := testhelper.StartStack(ctx, testhelper.StackOptions{
		Postgres: true, Cache: true, Kv: true, Storage: true,
	})
	if err != nil {
		t.Fatalf("StartStack() error = %v", err)
	}
	t.Cleanup(func() {
		if teardownErr := stack.Terminate(context.Background()); teardownErr != nil {
			t.Errorf("Terminate() error = %v", teardownErr)
		}
	})

	postgres := testhelper.PresetRequireEntry(t, stack.Postgres.Block, testhelper.PresetDefaultKey)
	cache := testhelper.PresetRequireEntry(t, stack.Cache.Block, testhelper.PresetDefaultKey)
	kv := testhelper.PresetRequireEntry(t, stack.Kv.Block, testhelper.PresetDefaultKey)
	storage := testhelper.PresetRequireEntry(t, stack.Storage.Block, testhelper.PresetDefaultKey)

	dialable(t, "postgres", postgres.Host, postgres.Port)
	dialable(t, "cache", cache.Host, cache.Port)
	dialable(t, "kv", kv.Host, kv.Port)
	if cache.Port == kv.Port {
		t.Fatalf("cache and kv share port %d, want two independent containers", cache.Port)
	}

	// The storage preset promises the bucket its block names already exists.
	request, err := http.NewRequestWithContext(ctx, http.MethodHead, storage.Endpoint+"/"+storage.Bucket, nil)
	if err != nil {
		t.Fatalf("NewRequest() error = %v", err)
	}
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		t.Fatalf("HEAD bucket error = %v", err)
	}
	defer func() { _ = response.Body.Close() }()
	if response.StatusCode == http.StatusNotFound {
		t.Fatal("HEAD bucket = 404, want the bucket the block names to exist")
	}

	// The emitted document is exactly what the preset schemas accept, so a
	// consumer composes it into a test configuration without translating it.
	blocks := stack.Blocks()
	if len(blocks) != 4 {
		t.Fatalf("blocks = %v, want all four presets", blocks)
	}
	problems, err := standardconfig.NewProblems(testhelper.ProblemSampleErrorPortal())
	if err != nil {
		t.Fatalf("NewProblems() error = %v", err)
	}
	if err := standardconfig.ValidateKeys(problems, standardconfig.PostgresBlockKey, stack.Postgres.Block); err != nil {
		t.Fatalf("ValidateKeys() error = %v, want the emitted keys to satisfy the preset contract", err)
	}
}

// dialable proves the emitted host and port reach a listening dependency.
func dialable(t *testing.T, label string, host string, port int) {
	t.Helper()
	address := net.JoinHostPort(host, strconv.Itoa(port))
	dialer := &net.Dialer{Timeout: 15 * time.Second}
	connection, err := dialer.DialContext(t.Context(), "tcp", address)
	if err != nil {
		t.Fatalf("%s at %s is not reachable: %v", label, address, err)
	}
	if err := connection.Close(); err != nil {
		t.Fatalf("closing the %s connection failed: %v", label, err)
	}
}
