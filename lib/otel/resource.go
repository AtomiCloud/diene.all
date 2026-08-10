package otel

import (
	"maps"
	"strings"

	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
	semconv "go.opentelemetry.io/otel/semconv/v1.41.0"
)

// Semantic-convention resource attribute keys the service tree maps onto
// (C0 §4). They are taken from the SDK's semconv package rather than hand-typed,
// so a convention rename cannot silently change the wire.
var (
	// AttrDeploymentEnvironmentName carries the landscape.
	AttrDeploymentEnvironmentName = string(semconv.DeploymentEnvironmentNameKey)
	// AttrServiceNamespace carries the platform.
	AttrServiceNamespace = string(semconv.ServiceNamespaceKey)
	// AttrServiceName carries the service.
	AttrServiceName = string(semconv.ServiceNameKey)
	// AttrServiceVersion carries the version.
	AttrServiceVersion = string(semconv.ServiceVersionKey)
)

// Raw AtomiCloud taxonomy attribute keys. They ship ALONGSIDE the semantic
// conventions so queries can address the unmapped coordinate (module) and the
// untranslated taxonomy directly.
const (
	// AttrAtomiLandscape is the raw landscape attribute.
	AttrAtomiLandscape = "atomi.landscape"
	// AttrAtomiPlatform is the raw platform attribute.
	AttrAtomiPlatform = "atomi.platform"
	// AttrAtomiService is the raw service attribute.
	AttrAtomiService = "atomi.service"
	// AttrAtomiModule is the raw module attribute.
	AttrAtomiModule = "atomi.module"
	// AttrAtomiVersion is the raw version attribute.
	AttrAtomiVersion = "atomi.version"
)

// Standard OTEL_* resource environment variables honored as an ops escape hatch.
const (
	// EnvResourceAttributes overrides or extends resource attributes.
	EnvResourceAttributes = "OTEL_RESOURCE_ATTRIBUTES"
	// EnvServiceName overrides service.name.
	EnvServiceName = "OTEL_SERVICE_NAME"
)

// ResourceAttributes maps a service-tree identity onto the canonical resource
// attribute set: the four C0 §4 semantic conventions plus the five raw
// `atomi.*` taxonomy attributes.
func ResourceAttributes(identity AppIdentity) (map[string]string, error) {
	if identityErr := identity.Validate(); identityErr != nil {
		return nil, identityErr
	}
	app := identity.Trimmed()
	return map[string]string{
		AttrDeploymentEnvironmentName: app.Landscape,
		AttrServiceNamespace:          app.Platform,
		AttrServiceName:               app.Service,
		AttrServiceVersion:            app.Version,
		AttrAtomiLandscape:            app.Landscape,
		AttrAtomiPlatform:             app.Platform,
		AttrAtomiService:              app.Service,
		AttrAtomiModule:               app.Module,
		AttrAtomiVersion:              app.Version,
	}, nil
}

// ParseResourceAttributes parses an OTEL_RESOURCE_ATTRIBUTES value in W3C
// baggage-like `key=value,key2=value2` form. Entries without a key are skipped
// rather than failing the process: an ops escape hatch must never be able to
// crash a service through a typo.
func ParseResourceAttributes(value string) map[string]string {
	attributes := map[string]string{}
	for entry := range strings.SplitSeq(value, ",") {
		trimmed := strings.TrimSpace(entry)
		if trimmed == "" {
			continue
		}
		name, attributeValue, found := strings.Cut(trimmed, "=")
		name = strings.TrimSpace(name)
		if !found || name == "" {
			continue
		}
		attributes[name] = strings.TrimSpace(attributeValue)
	}
	return attributes
}

// ResolvedResourceAttributes applies the standard OTEL_* overrides on top of the
// configured identity mapping: OTEL_RESOURCE_ATTRIBUTES entries win over the
// derived attributes, and OTEL_SERVICE_NAME wins over service.name. This is the
// C0 §4 ops escape hatch — the block never clobbers a set OTEL_* variable.
func ResolvedResourceAttributes(identity AppIdentity, system interfaces.System) (map[string]string, error) {
	configured, configuredErr := ResourceAttributes(identity)
	if configuredErr != nil {
		return nil, configuredErr
	}
	rawAttributes, rawErr := EnvValue(system, EnvResourceAttributes)
	if rawErr != nil {
		return nil, rawErr
	}
	if rawAttributes != nil {
		maps.Copy(configured, ParseResourceAttributes(*rawAttributes))
	}
	serviceName, serviceErr := EnvValue(system, EnvServiceName)
	if serviceErr != nil {
		return nil, serviceErr
	}
	if serviceName != nil && strings.TrimSpace(*serviceName) != "" {
		configured[AttrServiceName] = strings.TrimSpace(*serviceName)
	}
	return configured, nil
}
