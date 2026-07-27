package appconfig_test

import (
	"context"
	"errors"
	"reflect"
	"strings"
	"testing"

	"github.com/AtomiCloud/diene.go-config/lib/config"
	configtest "github.com/AtomiCloud/diene.go-config/testhelper"
	"github.com/AtomiCloud/diene.go-consumer/lib/appconfig"
)

const validDocument = `
app:
  landscape: lapras
  platform: diene
  service: go-consumer
  module: worker
  version: 1.0.0
otel:
  logs:
    enabled: true
    exporter:
      console: {enabled: false}
      otlp: {enabled: false, endpoint: '', protocol: http/protobuf, headers: {x-service: go-consumer}, timeout: PT10S}
  metrics:
    enabled: true
    exporter:
      console: {enabled: false}
      otlp: {enabled: false, endpoint: '', protocol: http/protobuf, headers: {x-service: go-consumer}, timeout: PT10S}
    interval: PT10S
  traces:
    enabled: true
    sampler: {type: parentbased_traceidratio, ratio: 1}
    exporter:
      console: {enabled: false}
      otlp: {enabled: false, endpoint: '', protocol: http/protobuf, headers: {x-service: go-consumer}, timeout: PT10S}
auth:
  idp:
    issuer: https://identity.example.test
    audience: go-consumer
    jwksUri: https://identity.example.test/oidc/jwks
    algorithms: [RS256]
    clockSkewSeconds: 30
    management:
      endpoint: https://identity.example.test/api
      resource: https://identity.example.test/api
      clientId: ''
      clientSecret: ''
  minting:
    tokenEndpoint: https://identity.example.test/oidc/token
    clientId: ''
    clientSecret: ''
    handoffPath: /app-handoff
    cacheNamespace: go-consumer
    refreshSkewSeconds: 30
    concurrency: 2
  resources: []
  policies: {}
api:
  backends:
    control:
      baseUrl: https://control.example.test
      resource: control
      indicator: https://control.example.test
      scopes: [read]
      timeout: PT15S
  retry: {network: true, delay: PT0.1S}
postgres:
  MAIN:
    host: postgres
    port: 5432
    database: go_consumer
    username: go_consumer
    password: ''
    ssl: false
    pool: {min: 0, max: 10}
cache:
  MAIN: {host: cache, port: 6379, password: '', db: 0, tls: false}
kv:
  MAIN: {host: kv, port: 6379, password: '', db: 1, tls: false}
storage:
  MAIN:
    endpoint: http://minio:9000
    region: us-east-1
    bucket: go-consumer
    accessKeyId: ''
    secretAccessKey: ''
    forcePathStyle: true
  ARCHIVE:
    endpoint: http://minio:9000
    region: us-east-1
    bucket: go-consumer-archive
    accessKeyId: ''
    secretAccessKey: ''
    forcePathStyle: true
encryption: {key: ''}
transport:
  stream: go-consumer.messages
  consumerGroup: go-consumer
  consumerName: worker-main
  blockMs: 1000
  idleMs: 5000
  batchSize: 10
errorPortal:
  scheme: https
  host: errors.example.test
  landscape: lapras
  platform: diene
  service: go-consumer
  module: worker
  version: v1
domain: {blobPrefix: processed, maxMessageBytes: 1048576}
dbInit:
  createBucket: false
  migrationsDir: migrations/pg
  redisMigrationKey: go-consumer:migrations:v1
  seedDir: seed
health: {heartbeatFile: dist/run/worker-heartbeat.json, maxAgeMs: 30000}
`

func sources(environment map[string]string) appconfig.LoadSources {
	return appconfig.LoadSources{
		Base: configtest.BaseSource(validDocument),
		Overlays: map[string]config.YAMLSource{
			"pichu": configtest.OverlaySource("pichu", `
app: {landscape: pichu}
transport: {consumerName: overlay-worker}
errorPortal: {landscape: pichu}
`),
		},
		Environment: configtest.EnvSource(environment),
	}
}

func TestLoadAppliesBaseOverlayAndEnvironment(t *testing.T) {
	t.Parallel()

	loaded, err := appconfig.Load(context.Background(), appconfig.LoadOptions{
		Landscape: "pichu",
		Sources: sources(map[string]string{
			"ATOMI_TRANSPORT__CONSUMERNAME": "environment-worker",
		}),
	})
	if err != nil {
		issues, _ := config.ValidationIssues(err)
		t.Fatalf("Load() error = %v, issues = %#v", err, issues)
	}
	if loaded.App.Landscape != "pichu" || loaded.Transport.ConsumerName != "environment-worker" {
		t.Fatalf("Load() = landscape %q, consumer %q", loaded.App.Landscape, loaded.Transport.ConsumerName)
	}
	if len(loaded.Storage) != 2 || loaded.ErrorPortal.Portal().Service != "go-consumer" {
		t.Fatalf("decoded config lost keyed storage or portal: %#v", loaded)
	}
}

func TestBlankEnvironmentValueIsUnset(t *testing.T) {
	t.Parallel()

	loaded, err := appconfig.LoadFromSources(
		context.Background(),
		"pichu",
		sources(map[string]string{"ATOMI_TRANSPORT__CONSUMERNAME": ""}),
	)
	if err != nil {
		issues, _ := config.ValidationIssues(err)
		t.Fatalf("LoadFromSources() error = %v, issues = %#v", err, issues)
	}
	if loaded.Transport.ConsumerName != "overlay-worker" {
		t.Fatalf("blank environment replaced overlay with %q", loaded.Transport.ConsumerName)
	}
}

func TestLoadRejectsInvalidFinalMerge(t *testing.T) {
	t.Parallel()

	_, err := appconfig.LoadFromSources(
		context.Background(),
		"",
		sources(map[string]string{"ATOMI_TRANSPORT__BATCHSIZE": "0"}),
	)
	issues, _ := config.ValidationIssues(err)
	if err == nil || len(issues) == 0 || !strings.Contains(strings.ToLower(issues[0].Path), "batchsize") {
		t.Fatalf("LoadFromSources() error = %v, issues = %#v, want batchSize validation", err, issues)
	}
}

func TestLoadPropagatesSchemaReflectionFailure(t *testing.T) {
	t.Parallel()

	want := errors.New("reflect failed")
	_, err := appconfig.LoadFromSourcesWith(
		context.Background(),
		"",
		sources(nil),
		func(any) (map[string]any, error) { return nil, want },
	)
	if !errors.Is(err, want) {
		t.Fatalf("LoadFromSourcesWith() error = %v, want %v", err, want)
	}
}

func TestSchemaAndConstants(t *testing.T) {
	t.Parallel()

	blocks, err := appconfig.OwnBlocksWith(config.FragmentFromType)
	if err != nil {
		t.Fatalf("OwnBlocks() error = %v", err)
	}
	wantKeys := []string{"encryption", "transport", "errorPortal", "domain", "dbInit", "health"}
	gotKeys := make([]string, 0, len(blocks))
	for _, block := range blocks {
		gotKeys = append(gotKeys, block.Key)
		if !block.Required {
			t.Fatalf("block %q is optional", block.Key)
		}
	}
	if !reflect.DeepEqual(gotKeys, wantKeys) {
		t.Fatalf("OwnBlocks() keys = %v, want %v", gotKeys, wantKeys)
	}

	schema, err := appconfig.SchemaWith(config.FragmentFromType)
	if err != nil {
		t.Fatalf("Schema() error = %v", err)
	}
	required, ok := schema.Root()["required"].([]any)
	if !ok || len(required) != 14 {
		t.Fatalf("Schema() required = %#v", schema.Root()["required"])
	}

	constants := appconfig.KeyedAdapterConstants()
	wantConstants := map[string][]string{
		"cache": {"MAIN"}, "kv": {"MAIN"}, "postgres": {"MAIN"}, "storage": {"ARCHIVE", "MAIN"},
	}
	if !reflect.DeepEqual(constants, wantConstants) {
		t.Fatalf("KeyedAdapterConstants() = %#v, want %#v", constants, wantConstants)
	}
	constants["storage"][0] = "MUTATED"
	if appconfig.KeyedAdapterConstants()["storage"][0] != appconfig.StorageArchive {
		t.Fatal("KeyedAdapterConstants() returned shared mutable storage")
	}
}

func TestSchemaReflectionFailures(t *testing.T) {
	t.Parallel()

	want := errors.New("reflection failed")
	failing := func(any) (map[string]any, error) { return nil, want }
	if _, err := appconfig.OwnBlocksWith(failing); !errors.Is(err, want) {
		t.Fatalf("OwnBlocksWith() error = %v, want %v", err, want)
	}
	if _, err := appconfig.SchemaWith(failing); !errors.Is(err, want) {
		t.Fatalf("SchemaWith() error = %v, want %v", err, want)
	}
}

func TestDecodeFailures(t *testing.T) {
	t.Parallel()

	if _, err := appconfig.Decode(configtest.StubConfig(map[string]any{})); err == nil {
		t.Fatal("Decode() accepted a config without app")
	}
	appOnly := configtest.StubApp(config.AppBlock{
		Landscape: "lapras", Platform: "diene", Service: "go-consumer", Module: "worker", Version: "1.0.0",
	})
	if _, err := appconfig.Decode(appOnly); err == nil {
		t.Fatal("Decode() accepted a config without engine blocks")
	}
}
