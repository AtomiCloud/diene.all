package otel_test

import (
	"crypto/sha256"
	"encoding/hex"
	"reflect"
	"testing"

	"github.com/AtomiCloud/diene.go-otel/lib/otel"
)

func TestJSONSchemaOwnsTheCanonicalBlock(t *testing.T) {
	t.Parallel()

	if otel.SchemaKey() != "otel" || otel.BlockKey != "otel" {
		t.Fatal("canonical schema key changed")
	}
	schema := otel.JSONSchema()
	rootAdditionalProperties, rootAdditionalPropertiesOK := schema["additionalProperties"].(bool)
	if schema["type"] != "object" || !rootAdditionalPropertiesOK || rootAdditionalProperties {
		t.Fatalf("root schema is not strict: %#v", schema)
	}
	properties, ok := schema["properties"].(map[string]any)
	if !ok || len(properties) != 3 {
		t.Fatalf("unexpected signal properties %#v", schema["properties"])
	}
	for _, signal := range otel.C0Otel.SignalKeys {
		signalSchema, signalOK := properties[signal].(map[string]any)
		signalAdditionalProperties, strictOK := signalSchema["additionalProperties"].(bool)
		if !signalOK || !strictOK || signalAdditionalProperties {
			t.Errorf("signal %q is not a strict object: %#v", signal, signalSchema)
		}
	}
	exporter := otel.ExporterSchema()
	exporterAdditionalProperties, strictOK := exporter["additionalProperties"].(bool)
	if !strictOK || exporterAdditionalProperties {
		t.Fatal("exporter schema is not strict")
	}
	exporterProperties, exporterPropertiesOK := exporter["properties"].(map[string]any)
	otlpSchema, otlpSchemaOK := exporterProperties["otlp"].(map[string]any)
	otlpProperties, otlpPropertiesOK := otlpSchema["properties"].(map[string]any)
	protocol, protocolOK := otlpProperties["protocol"].(map[string]any)
	if !exporterPropertiesOK || !otlpSchemaOK || !otlpPropertiesOK || !protocolOK {
		t.Fatalf("unexpected exporter schema %#v", exporter)
	}
	if !reflect.DeepEqual(protocol["enum"], []any{otel.ProtocolHTTPProtobuf}) {
		t.Fatalf("unexpected protocol enum %#v", protocol["enum"])
	}
	headers, headersOK := otlpProperties["headers"].(map[string]any)
	headerValues, headerValuesOK := headers["additionalProperties"].(map[string]any)
	if !headersOK || !headerValuesOK || headerValues["type"] != "string" {
		t.Fatal("header values must be strings")
	}
	duration := otel.DurationSchema("test duration")
	if duration["type"] != "string" || duration["description"] != "ISO 8601 duration: test duration" {
		t.Fatalf("unexpected duration schema %#v", duration)
	}
	sampler := otel.SamplerSchema()
	samplerProperties, samplerPropertiesOK := sampler["properties"].(map[string]any)
	typeSchema, typeSchemaOK := samplerProperties["type"].(map[string]any)
	if !samplerPropertiesOK || !typeSchemaOK {
		t.Fatalf("unexpected sampler schema %#v", sampler)
	}
	if !reflect.DeepEqual(typeSchema["enum"], otel.SamplerEnum()) {
		t.Fatal("sampler schema and vocabulary diverged")
	}
	wantEnum := []any{"parentbased_traceidratio", "always_on", "always_off"}
	if !reflect.DeepEqual(otel.SamplerEnum(), wantEnum) {
		t.Fatalf("unexpected sampler enum %#v", otel.SamplerEnum())
	}
}

func TestC0OtelContractVectors(t *testing.T) {
	t.Parallel()

	contract := otel.C0Otel
	if contract.Provenance.ContractVersion != "1" || contract.Provenance.C0Section != "C0 §4 Otel" ||
		contract.Provenance.C0Source != "goals/c0-contracts.md" {
		t.Fatalf("unexpected provenance %#v", contract.Provenance)
	}
	if !reflect.DeepEqual(contract.SignalKeys, []string{"logs", "metrics", "traces"}) ||
		!reflect.DeepEqual(contract.ExporterKeys, []string{"console", "otlp"}) ||
		!reflect.DeepEqual(contract.OtlpKeys, []string{"enabled", "endpoint", "protocol", "headers", "timeout"}) {
		t.Fatal("canonical key vocabulary changed")
	}
	if contract.Protocol != otel.ProtocolHTTPProtobuf || contract.OtlpPort != otel.OtlpHTTPPort ||
		contract.DefaultTimeout != otel.DefaultExportTimeout ||
		contract.DefaultInterval != otel.DefaultMetricInterval ||
		contract.DefaultSampler != otel.SamplerParentBasedTraceIDRatio.String() ||
		contract.DefaultRatio != otel.DefaultSamplerRatio {
		t.Fatalf("canonical defaults changed: %#v", contract)
	}
	if contract.SemconvMapping["landscape"] != otel.AttrDeploymentEnvironmentName ||
		contract.SemconvMapping["platform"] != otel.AttrServiceNamespace ||
		contract.SemconvMapping["service"] != otel.AttrServiceName ||
		contract.SemconvMapping["version"] != otel.AttrServiceVersion {
		t.Fatalf("semconv vector changed: %#v", contract.SemconvMapping)
	}
	payload := contract.DigestPayload()
	digest := sha256.Sum256([]byte(payload))
	gotDigest := hex.EncodeToString(digest[:])
	const wantDigest = "b7fdf9de30d4182b51a47fa300d2ec33916d1de1ad67eff777e48dc6453e8dd4"
	if gotDigest != wantDigest {
		t.Fatalf("C0 vector digest changed: want %s, got %s", wantDigest, gotDigest)
	}
}
