package preview

import (
	"strings"

	"github.com/AtomiCloud/diene.go-api-engine/lib/apiengine"
	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
	"github.com/AtomiCloud/diene.go-config/lib/config"
	"github.com/AtomiCloud/diene.go-e2e/lib/e2e"
	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
	"github.com/AtomiCloud/diene.go-otel/lib/otel"
	"github.com/AtomiCloud/diene.go-standard-config/lib/standardconfig"
)

// Environment variables the harness reads to locate the Garden preview
// environment. They are prefixed rather than reusing the service's own
// ATOMI_-prefixed configuration because the harness is a SEPARATE actor: it
// addresses the environment from outside, and borrowing the service's own keys
// would make a misconfigured suite silently reconfigure the system under test.
const (
	// EnvLandscape names the preview landscape. Optional; defaults to
	// [DefaultLandscape].
	EnvLandscape = "E2E_PREVIEW_LANDSCAPE"
	// EnvPlatform names the preview platform segment of the service tree.
	EnvPlatform = "E2E_PREVIEW_PLATFORM"
	// EnvService names the preview service segment of the service tree.
	EnvService = "E2E_PREVIEW_SERVICE"
	// EnvModule names the preview module segment of the service tree.
	EnvModule = "E2E_PREVIEW_MODULE"
	// EnvVersion names the deployed version under test.
	EnvVersion = "E2E_PREVIEW_VERSION"
	// EnvBaseURL is the preview service's origin.
	EnvBaseURL = "E2E_PREVIEW_BASE_URL"
	// EnvOtlpEndpoint is the preview environment's OTLP collector endpoint.
	EnvOtlpEndpoint = "E2E_PREVIEW_OTLP_ENDPOINT"
	// EnvIssuer is the preview IdP's OIDC issuer.
	EnvIssuer = "E2E_PREVIEW_ISSUER"
	// EnvAudience is the audience the preview IdP mints tokens for.
	EnvAudience = "E2E_PREVIEW_AUDIENCE"
	// EnvJWKSURI is the preview IdP's JWKS document.
	EnvJWKSURI = "E2E_PREVIEW_JWKS_URI"
	// EnvResource names the api-engine backend and auth resource the suite
	// drives. Optional; defaults to [DefaultResource].
	EnvResource = "E2E_PREVIEW_RESOURCE"
)

const (
	// DefaultLandscape is the preview landscape a target assumes when the
	// environment names none.
	DefaultLandscape = "garden"
	// DefaultResource is the backend and auth-resource name a target assumes
	// when the environment names none.
	DefaultResource = "primary"
)

// Target is a resolved Garden preview environment.
//
// Every field is a value the harness was TOLD, never one it guessed, which is
// what makes a SIT report attributable to a specific deployment.
type Target struct {
	// Landscape is the preview landscape, e.g. garden.
	Landscape string
	// Platform is the platform segment of the service tree.
	Platform string
	// Service is the service segment of the service tree.
	Service string
	// Module is the module segment of the service tree.
	Module string
	// Version is the deployed version under test.
	Version string
	// BaseURL is the preview service's origin.
	BaseURL string
	// OtlpEndpoint is the preview environment's OTLP collector endpoint.
	OtlpEndpoint string
	// Issuer is the preview IdP's OIDC issuer.
	Issuer string
	// Audience is the audience the preview IdP mints tokens for.
	Audience string
	// JWKSURI is the preview IdP's JWKS document.
	JWKSURI string
	// Resource names the api-engine backend and the auth resource the suite
	// drives.
	Resource string
}

// Resolve reads the preview target out of the environment through system.
//
// It is total on the read: an environment the seam cannot read at all is a
// [e2e.ProblemTargetUnreadable], and a target missing a setting the harness
// cannot invent is a [e2e.ProblemTargetIncomplete]. Neither degrades into a
// default, because a SIT suite that silently retargets itself is worse than one
// that refuses to start.
func Resolve(system interfaces.System, problems *e2e.Problems) (Target, error) {
	if problems == nil {
		return Target{}, errUnconfigured("problems")
	}
	if system == nil {
		return Target{}, problems.Raise(
			e2e.ProblemTargetUnreadable,
			"resolving a preview target needs a system seam",
			map[string]any{"component": "system"},
		)
	}
	reader := environmentReader{system: system, problems: problems}
	target := Target{
		Landscape:    DefaultLandscape,
		Resource:     DefaultResource,
		Platform:     "",
		Service:      "",
		Module:       "",
		Version:      "",
		BaseURL:      "",
		OtlpEndpoint: "",
		Issuer:       "",
		Audience:     "",
		JWKSURI:      "",
	}
	fields := []struct {
		name  string
		apply func(string)
	}{
		{EnvLandscape, func(value string) { target.Landscape = orKeep(target.Landscape, value) }},
		{EnvResource, func(value string) { target.Resource = orKeep(target.Resource, value) }},
		{EnvPlatform, func(value string) { target.Platform = value }},
		{EnvService, func(value string) { target.Service = value }},
		{EnvModule, func(value string) { target.Module = value }},
		{EnvVersion, func(value string) { target.Version = value }},
		{EnvBaseURL, func(value string) { target.BaseURL = value }},
		{EnvOtlpEndpoint, func(value string) { target.OtlpEndpoint = value }},
		{EnvIssuer, func(value string) { target.Issuer = value }},
		{EnvAudience, func(value string) { target.Audience = value }},
		{EnvJWKSURI, func(value string) { target.JWKSURI = value }},
	}
	for _, field := range fields {
		value, err := reader.read(field.name)
		if err != nil {
			return Target{}, err
		}
		field.apply(value)
	}
	if err := target.Validate(problems); err != nil {
		return Target{}, err
	}
	return target, nil
}

// Validate proves the target names a usable preview environment.
//
// The OTLP endpoint is checked with the otel sibling's own validator rather
// than a second implementation here, so the harness and the runtime agree on
// what a valid endpoint is (D2), and the C0-frozen http/protobuf port is
// asserted rather than assumed.
func (t Target) Validate(problems *e2e.Problems) error {
	if problems == nil {
		return errUnconfigured("problems")
	}
	required := []struct {
		name  string
		value string
	}{
		{EnvPlatform, t.Platform},
		{EnvService, t.Service},
		{EnvModule, t.Module},
		{EnvVersion, t.Version},
		{EnvBaseURL, t.BaseURL},
		{EnvOtlpEndpoint, t.OtlpEndpoint},
		{EnvIssuer, t.Issuer},
		{EnvAudience, t.Audience},
		{EnvJWKSURI, t.JWKSURI},
	}
	for _, field := range required {
		if strings.TrimSpace(field.value) == "" {
			return problems.Raise(
				e2e.ProblemTargetIncomplete,
				"the preview target is missing "+field.name,
				map[string]any{"variable": field.name},
			)
		}
	}
	// The endpoint is validated by the otel sibling's OWN validator and by
	// nothing else here. It already enforces the C0-frozen http/protobuf port
	// ([otel.OtlpHTTPPort]), and a second check in the harness would eventually
	// disagree with it — rejecting an endpoint the runtime accepts is exactly the
	// drift D2 exists to prevent.
	if err := otel.ValidateOtlpEndpoint(t.OtlpEndpoint); err != nil {
		return problems.RaiseFrom(
			e2e.ProblemTargetIncomplete,
			err,
			"the preview OTLP endpoint is not a valid collector endpoint",
			map[string]any{"variable": EnvOtlpEndpoint, "endpoint": t.OtlpEndpoint, "port": otel.OtlpHTTPPort},
		)
	}
	return nil
}

// Identity returns the target's otel application identity, which drives the
// semconv resource attributes a SIT run expects to see arrive at the collector.
func (t Target) Identity() otel.AppIdentity {
	return otel.AppIdentity{
		Landscape: t.Landscape,
		Platform:  t.Platform,
		Service:   t.Service,
		Module:    t.Module,
		Version:   t.Version,
	}
}

// AppBlock returns the target's `app:` configuration block (C0 §3).
func (t Target) AppBlock() config.AppBlock {
	return config.AppBlock{
		Landscape: t.Landscape,
		Platform:  t.Platform,
		Service:   t.Service,
		Module:    t.Module,
		Version:   t.Version,
	}
}

// OtelConfig returns the otel block a SIT run against this target implies: all
// three signals on, exporting OTLP http/protobuf to the preview collector.
//
// This is exactly the landscape-overlay flip D2 describes. The exporter is
// off by default everywhere else; SIT is the tier that turns it on, because SIT
// is the only tier with a real collector to turn it on against.
func (t Target) OtelConfig() otel.Config {
	base := otel.DefaultConfig()
	base.Logs.Enabled = true
	base.Metrics.Enabled = true
	base.Traces.Enabled = true
	base.Logs.Exporter = t.exporter()
	base.Metrics.Exporter = t.exporter()
	base.Traces.Exporter = t.exporter()
	return base
}

// exporter builds the OTLP exporter block the three signals share.
func (t Target) exporter() otel.ExporterConfig {
	exporter := otel.DefaultExporterConfig()
	exporter.Otlp.Enabled = true
	exporter.Otlp.Endpoint = t.OtlpEndpoint
	exporter.Otlp.Protocol = otel.ProtocolHTTPProtobuf
	return exporter
}

// AuthConfig returns the auth-engine block pointing at the preview IdP, with
// the target's single resource registered.
func (t Target) AuthConfig() authengine.Config {
	return authengine.Config{
		IDP: authengine.IDPConfig{
			Issuer:     t.Issuer,
			Audience:   t.Audience,
			JWKSURI:    t.JWKSURI,
			Algorithms: authengine.DefaultAlgorithms,
		},
		Resources: []authengine.ResourceConfig{{
			Name:      t.Resource,
			Indicator: t.BaseURL,
			Scopes:    []string{},
		}},
	}
}

// APIConfig returns the api-engine block with the preview service registered as
// the target's single backend.
//
// One backend, one hostname: client-side routing between regions is deleted,
// and a second preview region is simply a second registered backend.
func (t Target) APIConfig() apiengine.Config {
	base := apiengine.DefaultConfig()
	base.Backends = map[string]apiengine.BackendConfig{
		t.Resource: {
			BaseURL:   t.BaseURL,
			Resource:  t.Resource,
			Indicator: t.BaseURL,
			Scopes:    []string{},
			Timeout:   apiengine.DefaultTimeout,
		},
	}
	return base
}

// EngineBlocks returns the engine and infra-preset blocks a service targeted by
// this harness composes into its root schema, in stable order.
//
// It is exported separately from [Schema] so a service can compose its OWN keys
// alongside them without this package having to know about them, which is the
// C0 §3 division: every engine owns its block, the service composes, and the
// config lib is the sole merger and validator.
//
// # The api-engine block is deliberately absent
//
// `github.com/AtomiCloud/diene.go-api-engine@v1.0.0` puts a JSON Schema
// `pattern` on its two ISO 8601 duration fields that uses a Perl negative
// lookahead. Go's regexp does not support it, so the config lib's validator
// cannot COMPILE a root schema containing that block — the failure is at schema
// compile time and takes the whole document with it, valid or not. Composing it
// would therefore break every consumer of this harness rather than validate
// anything, so it is left out until an api-engine patch drops the pattern (the
// otel sibling's DurationSchema, which ships no pattern for the same values, is
// the family precedent). A consumer still gets fully typed api configuration
// from [Target.APIConfig]; only schema validation of that one block is
// unavailable. The regression test in tests/unit/preview turns red the moment
// the block becomes compilable, which is the signal to add it back here.
func EngineBlocks() []config.Block {
	return []config.Block{
		config.AppBlockSchema(),
		config.NewBlock(otel.BlockKey, true, otel.JSONSchema()),
		config.NewBlock(authengine.ConfigBlockKey, true, authengine.ConfigBlockSchema()),
		config.NewBlock(standardconfig.PostgresBlockKey, false, standardconfig.PostgresSchema()),
		config.NewBlock(standardconfig.CacheBlockKey, false, standardconfig.CacheSchema()),
		config.NewBlock(standardconfig.KvBlockKey, false, standardconfig.KvSchema()),
		config.NewBlock(standardconfig.StorageBlockKey, false, standardconfig.StorageSchema()),
	}
}

// APIBlock returns the api-engine block on its own.
//
// It is separate from [EngineBlocks] for the reason documented there: composing
// it into a root schema is currently fatal at schema-compile time. It is
// exported so a consumer can compose it deliberately once api-engine ships the
// fix, and so the harness's own regression test can assert exactly which block
// is at fault rather than asserting that "something" is broken.
func APIBlock() config.Block {
	return config.NewBlock(apiengine.ConfigBlockKey, true, apiengine.ConfigBlockSchema())
}

// Schema returns the composed root schema a service targeted by this harness
// validates against.
//
// Composition happens HERE and validation happens in the config lib, which is
// the only merger and validator in the family. This function adds no keys of its
// own; a service with extra keys composes [EngineBlocks] plus its own instead.
func Schema() config.Schema {
	return config.ComposeSchema(EngineBlocks()...)
}

// environmentReader reads one variable at a time through the system seam,
// turning a seam failure into the harness's own typed problem.
type environmentReader struct {
	system   interfaces.System
	problems *e2e.Problems
}

// read returns the variable's value, or the empty string when it is unset.
// A blank value is an unset value (M33).
func (r environmentReader) read(name string) (string, error) {
	value, err := r.system.Environment(name)
	if err != nil {
		return "", r.problems.RaiseFrom(
			e2e.ProblemTargetUnreadable,
			err,
			"the preview environment variable could not be read",
			map[string]any{"variable": name},
		)
	}
	if value == nil {
		return "", nil
	}
	return strings.TrimSpace(*value), nil
}

// orKeep keeps a default when the environment supplied nothing.
func orKeep(fallback string, value string) string {
	if value == "" {
		return fallback
	}
	return value
}

// errUnconfigured reports a seam the package cannot substitute for and cannot
// describe as a problem either, because the problem factory is what is missing.
func errUnconfigured(component string) error {
	return &UnconfiguredError{Component: component}
}

// UnconfiguredError reports a required seam that was not supplied.
//
// It is a typed error rather than a problem envelope because it is raised when
// the problem factory itself is absent — the one failure the harness cannot
// describe in RFC 9457 terms.
type UnconfiguredError struct {
	// Component names the missing seam.
	Component string
}

// Error renders the missing seam.
func (e *UnconfiguredError) Error() string {
	return "preview: " + e.Component + " is required"
}
