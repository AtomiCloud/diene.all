package storage_test

import (
	"context"
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	storageadapter "github.com/AtomiCloud/diene.go-consumer/adapters/storage"
	"github.com/AtomiCloud/diene.go-consumer/adapters/tracing"
	"github.com/AtomiCloud/diene.go-consumer/lib/domain"
	interfaceshelper "github.com/AtomiCloud/diene.go-interfaces/testhelper"
	otelhelper "github.com/AtomiCloud/diene.go-otel/testhelper"
	"github.com/AtomiCloud/diene.go-standard-config/lib/standardconfig"
	standardhelper "github.com/AtomiCloud/diene.go-standard-config/testhelper"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/smithy-go"
)

func TestClientAgainstMinIO(t *testing.T) {
	ctx := context.Background()
	started, startErr := standardhelper.StartStorage(ctx, standardhelper.StorageOptions{})
	if startErr != nil {
		t.Fatalf("start MinIO: %v", startErr)
	}
	t.Cleanup(func() { _ = started.Terminate(ctx) })
	tracer, emitter, _ := newTracer(t)
	client, openErr := storageadapter.Open(ctx, started.Entry, tracer)
	if openErr != nil {
		t.Fatalf("open adapter: %v", openErr)
	}
	if err := client.Ping(ctx); err != nil {
		t.Fatalf("ping: %v", err)
	}
	if created, err := client.EnsureBucketCreated(ctx); err != nil || created {
		t.Fatalf("existing bucket: created=%t err=%v", created, err)
	}
	if err := client.EnsureBucket(ctx); err != nil {
		t.Fatalf("ensure existing bucket: %v", err)
	}
	if exists, err := client.Exists(ctx, "missing"); err != nil || exists {
		t.Fatalf("unexpected missing object: exists=%t err=%v", exists, err)
	}
	if content, found, err := client.Get(ctx, "missing"); err != nil || found || content != nil {
		t.Fatalf("unexpected missing get: content=%q found=%t err=%v", content, found, err)
	}
	content := []byte("encrypted payload")
	if err := client.Put(ctx, "messages/one", content, "application/octet-stream"); err != nil {
		t.Fatalf("put: %v", err)
	}
	stored, saveErr := client.Save(ctx, domain.SaveInput{
		Body: "saved payload", ContentType: "text/plain", Key: "messages/saved",
	})
	expectedLink := "s3://" + started.Entry.Bucket + "/messages/saved"
	if saveErr != nil || stored.Key != "messages/saved" || stored.Link != expectedLink {
		t.Fatalf("save: stored=%#v err=%v", stored, saveErr)
	}
	if exists, err := client.Exists(ctx, "messages/one"); err != nil || !exists {
		t.Fatalf("expected object: exists=%t err=%v", exists, err)
	}
	loaded, found, loadErr := client.Get(ctx, "messages/one")
	if loadErr != nil || !found || string(loaded) != string(content) {
		t.Fatalf("unexpected object: content=%q found=%t err=%v", loaded, found, loadErr)
	}
	if err := client.Delete(ctx, "messages/one"); err != nil {
		t.Fatalf("delete: %v", err)
	}
	if err := client.Delete(ctx, "messages/saved"); err != nil {
		t.Fatalf("delete saved object: %v", err)
	}

	newEntry := started.Entry
	newEntry.Bucket = "go-consumer-created"
	newClient, newOpenErr := storageadapter.Open(ctx, newEntry, tracer)
	if newOpenErr != nil {
		t.Fatalf("open new-bucket adapter: %v", newOpenErr)
	}
	created, createErr := newClient.EnsureBucketCreated(ctx)
	if createErr != nil || !created {
		t.Fatalf("create bucket: created=%t err=%v", created, createErr)
	}
	if err := newClient.Ping(ctx); err != nil {
		t.Fatalf("ping created bucket: %v", err)
	}
	if len(emitter.Records()) < 12 {
		t.Fatalf("expected storage traces, got %d", len(emitter.Records()))
	}
}

func TestConstructionValidation(t *testing.T) {
	t.Parallel()
	ctx := context.Background()
	tracer, _, _ := newTracer(t)
	valid := validEntry()
	tests := []struct {
		name   string
		mutate func(*standardconfig.StorageEntry)
	}{
		{"malformed endpoint", func(entry *standardconfig.StorageEntry) { entry.Endpoint = "://" }},
		{"endpoint scheme", func(entry *standardconfig.StorageEntry) { entry.Endpoint = "ftp://storage.invalid" }},
		{"endpoint host", func(entry *standardconfig.StorageEntry) { entry.Endpoint = "http:///missing" }},
		{"region", func(entry *standardconfig.StorageEntry) { entry.Region = "" }},
		{"bucket", func(entry *standardconfig.StorageEntry) { entry.Bucket = "" }},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			entry := valid
			test.mutate(&entry)
			if _, err := storageadapter.OpenWithFactory(ctx, entry, tracer, func(context.Context, standardconfig.StorageEntry) (storageadapter.API, error) {
				t.Fatal("factory must not run for invalid config")
				return nil, nil
			}); err == nil {
				t.Fatal("expected validation error")
			}
		})
	}
	if _, err := storageadapter.OpenWithFactory(ctx, valid, nil, func(context.Context, standardconfig.StorageEntry) (storageadapter.API, error) {
		return &fakeAPI{}, nil
	}); err == nil {
		t.Fatal("expected missing tracer error")
	}
	if _, err := storageadapter.OpenWithFactory(ctx, valid, tracer, nil); err == nil {
		t.Fatal("expected missing factory error")
	}
	factoryErr := errors.New("factory failed")
	if _, err := storageadapter.OpenWithFactory(ctx, valid, tracer, func(context.Context, standardconfig.StorageEntry) (storageadapter.API, error) {
		return nil, factoryErr
	}); !errors.Is(err, factoryErr) {
		t.Fatalf("expected factory error, got %v", err)
	}
	if _, err := storageadapter.New(nil, "bucket", "region", tracer); err == nil {
		t.Fatal("expected missing API error")
	}
	if _, err := storageadapter.New(&fakeAPI{}, "", "region", tracer); err == nil {
		t.Fatal("expected missing bucket error")
	}
	if _, err := storageadapter.New(&fakeAPI{}, "bucket", "", tracer); err == nil {
		t.Fatal("expected missing region error")
	}
	if _, err := storageadapter.New(&fakeAPI{}, "bucket", "region", nil); err == nil {
		t.Fatal("expected missing tracer error")
	}
	if _, err := storageadapter.OpenWithFactory(ctx, valid, tracer, func(context.Context, standardconfig.StorageEntry) (storageadapter.API, error) {
		return &fakeAPI{}, nil
	}); err != nil {
		t.Fatalf("open with factory: %v", err)
	}
}

func TestBucketAndOperationFailures(t *testing.T) {
	t.Parallel()
	ctx := context.Background()
	tracer, emitter, system := newTracer(t)
	driverErr := errors.New("driver failed")
	api := &fakeAPI{headBucketErr: driverErr}
	client, clientErr := storageadapter.New(api, "bucket", "eu-west-1", tracer)
	if clientErr != nil {
		t.Fatalf("construct adapter: %v", clientErr)
	}
	if err := client.Ping(ctx); !errors.Is(err, driverErr) {
		t.Fatalf("expected ping error, got %v", err)
	}
	if _, err := client.EnsureBucketCreated(ctx); !errors.Is(err, driverErr) {
		t.Fatalf("expected head bucket error, got %v", err)
	}

	api.headBucketErr = notFound("NoSuchBucket")
	api.createBucketErr = driverErr
	if _, err := client.EnsureBucketCreated(ctx); !errors.Is(err, driverErr) {
		t.Fatalf("expected create bucket error, got %v", err)
	}
	api.createBucketErr = nil
	created, createErr := client.EnsureBucketCreated(ctx)
	if createErr != nil || !created {
		t.Fatalf("expected created bucket: created=%t err=%v", created, createErr)
	}
	if api.createBucketInput == nil || api.createBucketInput.CreateBucketConfiguration == nil {
		t.Fatal("expected non-default region create configuration")
	}

	defaultRegionClient, defaultRegionErr := storageadapter.New(api, "bucket", "us-east-1", tracer)
	if defaultRegionErr != nil {
		t.Fatalf("construct default-region adapter: %v", defaultRegionErr)
	}
	if _, err := defaultRegionClient.EnsureBucketCreated(ctx); err != nil {
		t.Fatalf("create default-region bucket: %v", err)
	}
	if api.createBucketInput.CreateBucketConfiguration != nil {
		t.Fatal("us-east-1 must omit create configuration")
	}

	api.putErr = driverErr
	if err := client.Put(ctx, "key", []byte("value"), ""); !errors.Is(err, driverErr) {
		t.Fatalf("expected put error, got %v", err)
	}
	if _, err := client.Save(ctx, domain.SaveInput{Key: "key", Body: "value"}); !errors.Is(err, driverErr) {
		t.Fatalf("expected save error, got %v", err)
	}
	api.putErr = nil
	if err := client.Put(ctx, "key", nil, "text/plain"); err != nil {
		t.Fatalf("put with content type: %v", err)
	}
	if api.putInput.ContentType == nil || aws.ToString(api.putInput.ContentType) != "text/plain" {
		t.Fatal("expected content type")
	}
	if err := client.Put(ctx, " ", nil, ""); err == nil {
		t.Fatal("expected blank put key error")
	}

	api.deleteErr = driverErr
	if err := client.Delete(ctx, "key"); !errors.Is(err, driverErr) {
		t.Fatalf("expected delete error, got %v", err)
	}
	if err := client.Delete(ctx, ""); err == nil {
		t.Fatal("expected blank delete key error")
	}
	if _, _, err := client.Get(ctx, " "); err == nil {
		t.Fatal("expected blank get key error")
	}
	if _, err := client.Exists(ctx, " "); err == nil {
		t.Fatal("expected blank exists key error")
	}

	clockErr := errors.New("clock failed")
	system.EnqueueClockResult(readClock(t, system), clockErr)
	if err := client.Ping(ctx); !errors.Is(err, clockErr) {
		t.Fatalf("expected clock error, got %v", err)
	}
	api.headBucketErr = nil
	emitErr := errors.New("emit failed")
	emitter.EnqueueResult(emitErr)
	if err := client.Ping(ctx); !errors.Is(err, emitErr) {
		t.Fatalf("expected emit error, got %v", err)
	}
}

func TestGetAndExistsFailurePaths(t *testing.T) {
	t.Parallel()
	ctx := context.Background()
	tracer, emitter, _ := newTracer(t)
	api := &fakeAPI{}
	client, err := storageadapter.New(api, "bucket", "region", tracer)
	if err != nil {
		t.Fatalf("construct adapter: %v", err)
	}

	api.getErr = notFound("NoSuchKey")
	if _, found, err := client.Get(ctx, "missing"); err != nil || found {
		t.Fatalf("expected API-code not found: found=%t err=%v", found, err)
	}
	api.getErr = statusError{status: 404}
	if _, found, err := client.Get(ctx, "missing-status"); err != nil || found {
		t.Fatalf("expected status not found: found=%t err=%v", found, err)
	}
	driverErr := errors.New("get failed")
	api.getErr = driverErr
	if _, _, err := client.Get(ctx, "failed"); !errors.Is(err, driverErr) {
		t.Fatalf("expected get error, got %v", err)
	}
	api.getErr = nil
	api.getOutput = nil
	if _, _, err := client.Get(ctx, "nil-output"); err == nil {
		t.Fatal("expected nil output error")
	}
	api.getOutput = &s3.GetObjectOutput{}
	if _, _, err := client.Get(ctx, "nil-body"); err == nil {
		t.Fatal("expected nil body error")
	}
	readErr := errors.New("read failed")
	api.getOutput = &s3.GetObjectOutput{Body: &failingBody{readErr: readErr}}
	if _, _, err := client.Get(ctx, "read-failed"); !errors.Is(err, readErr) {
		t.Fatalf("expected read error, got %v", err)
	}
	closeErr := errors.New("close failed")
	api.getOutput = &s3.GetObjectOutput{Body: &failingBody{content: "value", closeErr: closeErr}}
	if _, _, err := client.Get(ctx, "close-failed"); !errors.Is(err, closeErr) {
		t.Fatalf("expected close error, got %v", err)
	}
	api.getOutput = &s3.GetObjectOutput{Body: io.NopCloser(strings.NewReader("value"))}
	emitErr := errors.New("emit failed")
	emitter.EnqueueResult(emitErr)
	if _, _, err := client.Get(ctx, "emit-failed"); !errors.Is(err, emitErr) {
		t.Fatalf("expected get emit error, got %v", err)
	}

	api.headObjectErr = notFound("NotFound")
	if exists, err := client.Exists(ctx, "missing"); err != nil || exists {
		t.Fatalf("expected missing exists: exists=%t err=%v", exists, err)
	}
	api.headObjectErr = statusError{status: 404}
	if exists, err := client.Exists(ctx, "missing-status"); err != nil || exists {
		t.Fatalf("expected status missing exists: exists=%t err=%v", exists, err)
	}
	api.headObjectErr = driverErr
	if _, err := client.Exists(ctx, "failed"); !errors.Is(err, driverErr) {
		t.Fatalf("expected exists error, got %v", err)
	}
	api.headObjectErr = nil
	if exists, err := client.Exists(ctx, "present"); err != nil || !exists {
		t.Fatalf("expected present exists: exists=%t err=%v", exists, err)
	}
}

func TestOperationStartAndNotFoundEndFailures(t *testing.T) {
	t.Parallel()
	ctx := context.Background()
	tracer, emitter, system := newTracer(t)
	api := &fakeAPI{}
	client, constructErr := storageadapter.New(api, "bucket", "region", tracer)
	if constructErr != nil {
		t.Fatalf("construct adapter: %v", constructErr)
	}

	clockErr := errors.New("clock failed")
	tests := []struct {
		name string
		run  func() error
	}{
		{"ensure bucket", func() error { _, callErr := client.EnsureBucketCreated(ctx); return callErr }},
		{"put", func() error { return client.Put(ctx, "key", nil, "") }},
		{"get", func() error { _, _, callErr := client.Get(ctx, "key"); return callErr }},
		{"exists", func() error { _, callErr := client.Exists(ctx, "key"); return callErr }},
		{"delete", func() error { return client.Delete(ctx, "key") }},
	}
	for _, test := range tests {
		system.EnqueueClockResult(readClock(t, system), clockErr)
		if callErr := test.run(); !errors.Is(callErr, clockErr) {
			t.Fatalf("%s: expected clock failure, got %v", test.name, callErr)
		}
	}

	emitErr := errors.New("emit failed")
	api.getErr = notFound("NoSuchKey")
	emitter.EnqueueResult(emitErr)
	if _, _, getErr := client.Get(ctx, "missing"); !errors.Is(getErr, emitErr) {
		t.Fatalf("expected not-found get emit failure, got %v", getErr)
	}
	api.headObjectErr = notFound("NotFound")
	emitter.EnqueueResult(emitErr)
	if _, existsErr := client.Exists(ctx, "missing"); !errors.Is(existsErr, emitErr) {
		t.Fatalf("expected not-found exists emit failure, got %v", existsErr)
	}
}

func TestOpenReportsAWSConfigFailure(t *testing.T) {
	configPath := filepath.Join(t.TempDir(), "config")
	if writeErr := os.WriteFile(configPath, []byte("[invalid"), 0o600); writeErr != nil {
		t.Fatalf("write invalid AWS config: %v", writeErr)
	}
	t.Setenv("AWS_CONFIG_FILE", configPath)
	t.Setenv("AWS_PROFILE", "missing-profile")
	tracer, _, _ := newTracer(t)
	if _, openErr := storageadapter.Open(context.Background(), validEntry(), tracer); openErr == nil {
		t.Fatal("expected invalid AWS config failure")
	}
}

func validEntry() standardconfig.StorageEntry {
	return standardconfig.StorageEntry{
		Endpoint: "https://storage.invalid:9000", Region: "us-east-1", Bucket: "bucket",
		AccessKeyID: "access", SecretAccessKey: "secret", ForcePathStyle: true,
	}
}

func notFound(code string) error {
	return &smithy.GenericAPIError{Code: code, Message: "missing", Fault: smithy.FaultClient}
}

func newTracer(t *testing.T) (*tracing.Tracer, *otelhelper.InMemoryTraceEmitter, *interfaceshelper.InMemorySystem) {
	t.Helper()
	system := interfaceshelper.NewInMemorySystem(interfaceshelper.InMemorySystemOptions{})
	emitter := otelhelper.NewInMemoryTraceEmitter()
	tracer, err := tracing.New(system, emitter)
	if err != nil {
		t.Fatalf("construct tracer: %v", err)
	}
	return tracer, emitter, system
}

func readClock(t *testing.T, system *interfaceshelper.InMemorySystem) time.Time {
	t.Helper()
	now, err := system.NowUTC()
	if err != nil {
		t.Fatalf("read clock: %v", err)
	}
	return now
}

type statusError struct{ status int }

func (statusError) Error() string         { return "HTTP status error" }
func (s statusError) HTTPStatusCode() int { return s.status }

type failingBody struct {
	content  string
	read     bool
	readErr  error
	closeErr error
}

func (b *failingBody) Read(destination []byte) (int, error) {
	if b.readErr != nil {
		return 0, b.readErr
	}
	if b.read {
		return 0, io.EOF
	}
	b.read = true
	return copy(destination, b.content), nil
}

func (b *failingBody) Close() error { return b.closeErr }

type fakeAPI struct {
	headBucketErr     error
	createBucketErr   error
	createBucketInput *s3.CreateBucketInput
	putErr            error
	putInput          *s3.PutObjectInput
	getOutput         *s3.GetObjectOutput
	getErr            error
	headObjectErr     error
	deleteErr         error
}

func (f *fakeAPI) HeadBucket(context.Context, *s3.HeadBucketInput, ...func(*s3.Options)) (*s3.HeadBucketOutput, error) {
	return &s3.HeadBucketOutput{}, f.headBucketErr
}

func (f *fakeAPI) CreateBucket(_ context.Context, input *s3.CreateBucketInput, _ ...func(*s3.Options)) (*s3.CreateBucketOutput, error) {
	f.createBucketInput = input
	return &s3.CreateBucketOutput{}, f.createBucketErr
}

func (f *fakeAPI) PutObject(_ context.Context, input *s3.PutObjectInput, _ ...func(*s3.Options)) (*s3.PutObjectOutput, error) {
	f.putInput = input
	return &s3.PutObjectOutput{}, f.putErr
}

func (f *fakeAPI) GetObject(context.Context, *s3.GetObjectInput, ...func(*s3.Options)) (*s3.GetObjectOutput, error) {
	return f.getOutput, f.getErr
}

func (f *fakeAPI) HeadObject(context.Context, *s3.HeadObjectInput, ...func(*s3.Options)) (*s3.HeadObjectOutput, error) {
	return &s3.HeadObjectOutput{}, f.headObjectErr
}

func (f *fakeAPI) DeleteObject(context.Context, *s3.DeleteObjectInput, ...func(*s3.Options)) (*s3.DeleteObjectOutput, error) {
	return &s3.DeleteObjectOutput{}, f.deleteErr
}
