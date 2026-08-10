package compose_test

import (
	"testing"

	"github.com/AtomiCloud/diene.go-config/lib/config"
	"github.com/AtomiCloud/diene.go-otel/lib/otel"
	"github.com/AtomiCloud/diene.go-standard-config/lib/standardconfig"
)

// This suite is the R-E12 dogfood for two PUBLISHED artifacts. It composes a
// service root schema out of github.com/AtomiCloud/diene.go-config@v1.0.0's
// composition surface, github.com/AtomiCloud/diene.go-otel@v1.0.0's
// engine-owned block, and this library's infra presets, then drives the real
// three-layer load. Both siblings are resolved through the public Go proxy with
// NO replace directive and no path dependency, so this suite failing means the
// registry artifacts changed, not that a local checkout drifted.
//
// It is also the composition contract itself: C0 §3 puts the merger and
// validator in the config lib alone, and this is what "a service composes its
// own root schema" actually looks like.

// serviceSchema composes the root schema a Diene Go service would compose:
// config's own app block, the otel engine's block, the infra presets this
// library ships, and the service's own keys.
func serviceSchema(t *testing.T) config.Schema {
	t.Helper()
	return config.ComposeSchema(
		config.AppBlockSchema(),
		config.NewBlock(otel.BlockKey, false, otel.JSONSchema()),
		config.NewBlock(standardconfig.PostgresBlockKey, true, standardconfig.PostgresSchema()),
		config.NewBlock(standardconfig.CacheBlockKey, true, standardconfig.CacheSchema()),
		config.NewBlock(standardconfig.KvBlockKey, true, standardconfig.KvSchema()),
		config.NewBlock(standardconfig.StorageBlockKey, true, standardconfig.StorageSchema()),
	)
}

// baseDocument is the base YAML layer: full defaults, secrets blank (R14/M33),
// UPPERCASE connection names (R14).
const baseDocument = `
app:
  landscape: lapras
  platform: sulfoxide
  service: billing
  module: core
  version: 1.4.2
otel:
  logs:
    enabled: true
    exporter:
      console:
        enabled: false
      otlp:
        enabled: false
        endpoint: ""
        protocol: http/protobuf
        headers:
          x-atomi-tenant: billing
        timeout: PT10S
  metrics:
    enabled: true
    interval: PT60S
    exporter:
      console:
        enabled: false
      otlp:
        enabled: false
        endpoint: ""
        protocol: http/protobuf
        headers:
          x-atomi-tenant: billing
        timeout: PT10S
  traces:
    enabled: true
    sampler:
      type: parentbased_traceidratio
      ratio: 1.0
    exporter:
      console:
        enabled: false
      otlp:
        enabled: false
        endpoint: ""
        protocol: http/protobuf
        headers:
          x-atomi-tenant: billing
        timeout: PT10S
postgres:
  MAIN:
    host: postgres.invalid
    port: 5432
    database: billing
    username: billing
    password: ""
    ssl: false
    pool:
      min: 0
      max: 10
cache:
  MAIN:
    host: cache.invalid
    port: 6379
    password: ""
    db: 0
    tls: false
kv:
  MAIN:
    host: kv.invalid
    port: 6379
    password: ""
    db: 0
    tls: false
storage:
  ASSETS:
    endpoint: http://storage.invalid
    region: us-east-1
    bucket: assets
    accessKeyId: ""
    secretAccessKey: ""
    forcePathStyle: true
`

// overlayDocument is the sparse landscape overlay: it flips the infra to its
// cloud posture and adds a SECOND Postgres pool, which is the keyed
// multi-instance contract — YAML only, no schema change.
const overlayDocument = `
postgres:
  MAIN:
    host: primary.lapras.invalid
    ssl: true
  REPLICA:
    host: replica.lapras.invalid
    port: 5432
    database: billing
    username: billing_ro
    password: ""
    ssl: true
    pool:
      min: 0
      max: 4
cache:
  MAIN:
    host: dragonfly.lapras.invalid
    tls: true
kv:
  MAIN:
    host: upstash.lapras.invalid
    tls: true
storage:
  ASSETS:
    endpoint: https://fly.storage.tigris.dev
    forcePathStyle: false
otel:
  traces:
    exporter:
      otlp:
        enabled: true
        endpoint: http://collector:4318
`

// loaderFor builds the loader over the three layers with the composed schema.
func loaderFor(t *testing.T, base, overlay string, env map[string]string) *config.Loader {
	t.Helper()
	return config.NewLoader(
		config.WithEnvPrefix("ATOMI_"),
		config.WithSchema(serviceSchema(t)),
		config.WithBaseSource(config.NewBytesYAMLSource("base", []byte(base))),
		config.WithOverlaySource("lapras", config.NewBytesYAMLSource("lapras", []byte(overlay))),
		config.WithEnvSource(config.NewMapEnvSource("env", env)),
	)
}
