package preview_test

import (
	"errors"
	"testing"

	"github.com/AtomiCloud/diene.go-api-engine/lib/apiengine"
	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
	"github.com/AtomiCloud/diene.go-config/lib/config"
	"github.com/AtomiCloud/diene.go-e2e/lib/e2e"
	"github.com/AtomiCloud/diene.go-e2e/lib/preview"
	"github.com/AtomiCloud/diene.go-otel/lib/otel"
	"github.com/AtomiCloud/diene.go-standard-config/lib/standardconfig"
)

func TestResolveNeedsAProblemFactory(t *testing.T) {
	t.Parallel()

	_, err := preview.Resolve(systemWith(completeEnvironment()), nil)
	var unconfigured *preview.UnconfiguredError
	if !errors.As(err, &unconfigured) {
		t.Fatalf("Resolve() error = %v, want an UnconfiguredError", err)
	}
	if unconfigured.Component != "problems" {
		t.Fatalf("component = %q, want problems", unconfigured.Component)
	}
	if got := unconfigured.Error(); got != "preview: problems is required" {
		t.Fatalf("Error() = %q, want the unconfigured message", got)
	}
}

func TestResolveNeedsASystemSeam(t *testing.T) {
	t.Parallel()

	_, err := preview.Resolve(nil, requireProblems(t))
	if got := problemID(t, err); got != e2e.ProblemTargetUnreadable {
		t.Fatalf("problem id = %q, want %q", got, e2e.ProblemTargetUnreadable)
	}
	if problemData(t, err)["component"] != "system" {
		t.Fatalf("problem data = %v, want the system component", problemData(t, err))
	}
}

func TestResolveReportsAnUnreadableEnvironment(t *testing.T) {
	t.Parallel()

	system := systemWith(completeEnvironment())
	system.EnqueueEnvironmentResult(nil, errBoom)
	_, err := preview.Resolve(system, requireProblems(t))
	if got := problemID(t, err); got != e2e.ProblemTargetUnreadable {
		t.Fatalf("problem id = %q, want %q", got, e2e.ProblemTargetUnreadable)
	}
	if !errors.Is(err, errBoom) {
		t.Fatal("errors.Is(err, errBoom) = false, want the seam failure preserved")
	}
	if problemData(t, err)["variable"] != preview.EnvLandscape {
		t.Fatalf("problem data = %v, want the variable named", problemData(t, err))
	}
}

func TestResolveDefaultsLandscapeAndResource(t *testing.T) {
	t.Parallel()

	target := resolveComplete(t, nil)
	if target.Landscape != preview.DefaultLandscape {
		t.Fatalf("landscape = %q, want %q", target.Landscape, preview.DefaultLandscape)
	}
	if target.Resource != preview.DefaultResource {
		t.Fatalf("resource = %q, want %q", target.Resource, preview.DefaultResource)
	}
}

func TestResolveHonoursExplicitLandscapeAndResource(t *testing.T) {
	t.Parallel()

	target := resolveComplete(t, func(environment map[string]string) {
		environment[preview.EnvLandscape] = "pichu"
		environment[preview.EnvResource] = "reports"
	})
	if target.Landscape != "pichu" || target.Resource != "reports" {
		t.Fatalf("target = %+v, want the environment's landscape and resource", target)
	}
}

func TestResolveTrimsSurroundingWhitespace(t *testing.T) {
	t.Parallel()

	target := resolveComplete(t, func(environment map[string]string) {
		environment[preview.EnvService] = "  billing  "
	})
	if target.Service != "billing" {
		t.Fatalf("service = %q, want the trimmed value", target.Service)
	}
}

func TestResolveRefusesEveryMissingSetting(t *testing.T) {
	t.Parallel()

	required := []string{
		preview.EnvPlatform,
		preview.EnvService,
		preview.EnvModule,
		preview.EnvVersion,
		preview.EnvBaseURL,
		preview.EnvOtlpEndpoint,
		preview.EnvIssuer,
		preview.EnvAudience,
		preview.EnvJWKSURI,
	}
	for _, variable := range required {
		t.Run(variable, func(t *testing.T) {
			t.Parallel()
			environment := completeEnvironment()
			delete(environment, variable)
			_, err := preview.Resolve(systemWith(environment), requireProblems(t))
			if got := problemID(t, err); got != e2e.ProblemTargetIncomplete {
				t.Fatalf("problem id = %q, want %q", got, e2e.ProblemTargetIncomplete)
			}
			if problemData(t, err)["variable"] != variable {
				t.Fatalf("problem data = %v, want %q named", problemData(t, err), variable)
			}
		})
	}
}

func TestResolveTreatsABlankValueAsUnset(t *testing.T) {
	t.Parallel()

	environment := completeEnvironment()
	environment[preview.EnvBaseURL] = "   "
	_, err := preview.Resolve(systemWith(environment), requireProblems(t))
	if got := problemID(t, err); got != e2e.ProblemTargetIncomplete {
		t.Fatalf("problem id = %q, want %q", got, e2e.ProblemTargetIncomplete)
	}
}

func TestValidateNeedsAProblemFactory(t *testing.T) {
	t.Parallel()

	target := resolveComplete(t, nil)
	if err := target.Validate(nil); err == nil {
		t.Fatal("Validate() error = nil, want the unconfigured refusal")
	}
}

func TestIdentityAndAppBlockCarryTheServiceTree(t *testing.T) {
	t.Parallel()

	target := resolveComplete(t, nil)
	want := otel.AppIdentity{
		Landscape: preview.DefaultLandscape,
		Platform:  "sulfoxide",
		Service:   "billing",
		Module:    "core",
		Version:   "1.4.2",
	}
	if target.Identity() != want {
		t.Fatalf("Identity() = %+v, want %+v", target.Identity(), want)
	}
	block := target.AppBlock()
	wantBlock := config.AppBlock{
		Landscape: want.Landscape,
		Platform:  want.Platform,
		Service:   want.Service,
		Module:    want.Module,
		Version:   want.Version,
	}
	if block != wantBlock {
		t.Fatalf("AppBlock() = %+v, want %+v", block, wantBlock)
	}
}

func TestOtelConfigFlipsEverySignalOntoTheCollector(t *testing.T) {
	t.Parallel()

	target := resolveComplete(t, nil)
	got := target.OtelConfig()
	if !got.Logs.Enabled || !got.Metrics.Enabled || !got.Traces.Enabled {
		t.Fatalf("OtelConfig() = %+v, want all three signals enabled", got)
	}
	exporters := []otel.ExporterConfig{got.Logs.Exporter, got.Metrics.Exporter, got.Traces.Exporter}
	for index, exporter := range exporters {
		if !exporter.Otlp.Enabled {
			t.Fatalf("exporter %d = %+v, want OTLP enabled", index, exporter)
		}
		if exporter.Otlp.Endpoint != "http://alloy.garden.atomi.cloud:4318" {
			t.Fatalf("exporter %d endpoint = %q, want the preview collector", index, exporter.Otlp.Endpoint)
		}
		if exporter.Otlp.Protocol != otel.ProtocolHTTPProtobuf {
			t.Fatalf("exporter %d protocol = %q, want %q", index, exporter.Otlp.Protocol, otel.ProtocolHTTPProtobuf)
		}
		if exporter.Console.Enabled {
			t.Fatalf("exporter %d = %+v, want the console exporter left off", index, exporter)
		}
	}
	if otel.DefaultConfig().Traces.Exporter.Otlp.Enabled {
		t.Fatal("the otel default already enables OTLP, so the SIT flip proves nothing")
	}
}

func TestAuthConfigPointsAtThePreviewIdP(t *testing.T) {
	t.Parallel()

	target := resolveComplete(t, nil)
	got := target.AuthConfig()
	if got.IDP.Issuer != "https://logto.garden.atomi.cloud/oidc" {
		t.Fatalf("issuer = %q, want the preview issuer", got.IDP.Issuer)
	}
	if got.IDP.Audience != "https://billing.garden.atomi.cloud" {
		t.Fatalf("audience = %q, want the preview audience", got.IDP.Audience)
	}
	if got.IDP.JWKSURI != "https://logto.garden.atomi.cloud/oidc/jwks" {
		t.Fatalf("jwks = %q, want the preview jwks", got.IDP.JWKSURI)
	}
	if len(got.IDP.Algorithms) != len(authengine.DefaultAlgorithms) {
		t.Fatalf("algorithms = %v, want the auth-engine defaults", got.IDP.Algorithms)
	}
	if len(got.Resources) != 1 || got.Resources[0].Name != preview.DefaultResource {
		t.Fatalf("resources = %+v, want the single preview resource", got.Resources)
	}
	if got.Resources[0].Indicator != "https://billing.garden.atomi.cloud" {
		t.Fatalf("indicator = %q, want the preview origin", got.Resources[0].Indicator)
	}
}

func TestAPIConfigRegistersOneBackendPerHostname(t *testing.T) {
	t.Parallel()

	target := resolveComplete(t, nil)
	got := target.APIConfig()
	if len(got.Backends) != 1 {
		t.Fatalf("backends = %+v, want exactly one", got.Backends)
	}
	backend, found := got.Backends[preview.DefaultResource]
	if !found {
		t.Fatalf("backends = %+v, want one keyed by the resource", got.Backends)
	}
	if backend.BaseURL != "https://billing.garden.atomi.cloud" {
		t.Fatalf("base URL = %q, want the preview origin", backend.BaseURL)
	}
	if backend.Timeout != apiengine.DefaultTimeout {
		t.Fatalf("timeout = %v, want the api-engine default", backend.Timeout)
	}
	if got.Retry != apiengine.DefaultConfig().Retry {
		t.Fatalf("retry = %+v, want the api-engine retry-once profile untouched", got.Retry)
	}
}

func TestSchemaComposesEveryEngineBlockAndPreset(t *testing.T) {
	t.Parallel()

	raw := preview.Schema().Root()
	properties, valid := raw["properties"].(map[string]any)
	if !valid {
		t.Fatalf("schema document = %v, want an object with properties", raw)
	}
	want := []string{
		config.AppKey,
		otel.BlockKey,
		authengine.ConfigBlockKey,
		apiengine.ConfigBlockKey,
		standardconfig.PostgresBlockKey,
		standardconfig.CacheBlockKey,
		standardconfig.KvBlockKey,
		standardconfig.StorageBlockKey,
	}
	for _, key := range want {
		if _, found := properties[key]; !found {
			t.Fatalf("schema properties = %v, want %q composed in", properties, key)
		}
	}
	required, valid := raw["required"].([]any)
	if !valid {
		t.Fatalf("schema document = %v, want a required list", raw)
	}
	if len(required) != 4 {
		t.Fatalf("required = %v, want the app block plus the three engine blocks", required)
	}
}

func TestEngineBlocksAllCompileIntoARootSchema(t *testing.T) {
	t.Parallel()

	for _, block := range preview.EngineBlocks() {
		t.Run(block.Key, func(t *testing.T) {
			t.Parallel()
			// A schema-compile failure surfaces from Validate, not from
			// ComposeSchema, so validating an empty document is what proves the
			// block is compilable at all.
			err := config.ComposeSchema(block).Validate(map[string]any{})
			if err == nil {
				return
			}
			if _, isValidation := config.ValidationIssues(err); !isValidation {
				t.Fatalf("block %q does not compile: %v", block.Key, err)
			}
		})
	}
}

// TestEveryEngineBlockComposesIntoOneValidatableRootSchema is a PERMANENT GATE,
// not an ordinary assertion, and it must not be deleted.
//
// It exists because `diene.go-api-engine@v1.0.0` shipped a config block whose
// ISO 8601 duration `pattern` used a Perl negative lookahead. Go's regexp cannot
// compile it, so the family's SOLE merger/validator could not compile ANY root
// schema containing that block — which meant no go service could do what C0 §3
// requires of it. The defect was invisible to every other check: the block's Go
// API was fine, its schema was well-formed JSON, and reading the schema told you
// nothing. Only COMPOSING the blocks and asking the validator to run exposed it.
//
// So this gate composes ALL of them together and VALIDATES, and it proves the
// validator is genuinely live by requiring it to REJECT a document that omits a
// required block. A gate that only checked the happy path would pass just as
// well against a validator that had silently stopped compiling.
func TestEveryEngineBlockComposesIntoOneValidatableRootSchema(t *testing.T) {
	t.Parallel()

	blocks := preview.EngineBlocks()
	if len(blocks) != 8 {
		t.Fatalf("EngineBlocks() has %d blocks, want all 8 engine and preset blocks", len(blocks))
	}

	schema := preview.Schema()

	// A document carrying every required block must VALIDATE. If the root schema
	// failed to compile, this surfaces as a non-validation error rather than a
	// validation issue, which is exactly the failure mode the lookahead caused.
	complete := map[string]any{
		config.AppKey:                   appDocument(),
		otel.BlockKey:                   otelDocument(),
		authengine.ConfigBlockKey:       authDocument(),
		apiengine.ConfigBlockKey:        apiDocument(),
		standardconfig.PostgresBlockKey: postgresDocument(),
	}
	if err := schema.Validate(complete); err != nil {
		if _, isValidation := config.ValidationIssues(err); !isValidation {
			t.Fatalf("the composed root schema does not COMPILE: %v", err)
		}
		t.Fatalf("a complete document failed validation: %v", err)
	}

	// And the validator must still be enforcing. Drop a required block and it has
	// to refuse, otherwise this gate would pass against a dead validator.
	for _, block := range blocks {
		if !block.Required {
			continue
		}
		t.Run("rejects a document missing "+block.Key, func(t *testing.T) {
			t.Parallel()
			partial := map[string]any{}
			for key, value := range complete {
				if key != block.Key {
					partial[key] = value
				}
			}
			err := schema.Validate(partial)
			if err == nil {
				t.Fatalf("a document missing the required %q block validated; the validator is not enforcing", block.Key)
			}
			if _, isValidation := config.ValidationIssues(err); !isValidation {
				t.Fatalf("omitting %q produced a compile failure rather than a validation issue: %v", block.Key, err)
			}
		})
	}
}
