package otel

import "strings"

// AppIdentity is the service-tree `app:` coordinate every resource attribute is
// DERIVED from (C0 §4). Resource attributes are never hand-authored, so this is
// the only telemetry identity input a service supplies.
type AppIdentity struct {
	// Landscape is the LPSM `L` segment, mapped to deployment.environment.name.
	Landscape string `json:"landscape" yaml:"landscape"`
	// Platform is the LPSM `P` segment, mapped to service.namespace.
	Platform string `json:"platform" yaml:"platform"`
	// Service is the LPSM `S` segment, mapped to service.name.
	Service string `json:"service" yaml:"service"`
	// Module is the LPSM `M` segment. It has no semantic-convention counterpart
	// and travels only as atomi.module.
	Module string `json:"module" yaml:"module"`
	// Version is the released version, mapped to service.version.
	Version string `json:"version" yaml:"version"`
}

// Validate reports whether every coordinate is present. A blank coordinate would
// silently produce an unattributable telemetry stream, so it is fail-fast.
func (a AppIdentity) Validate() error {
	coordinates := []struct {
		name  string
		value string
	}{
		{name: "landscape", value: a.Landscape},
		{name: "platform", value: a.Platform},
		{name: "service", value: a.Service},
		{name: "module", value: a.Module},
		{name: "version", value: a.Version},
	}
	for _, coordinate := range coordinates {
		if strings.TrimSpace(coordinate.value) == "" {
			return NewFault(FaultIdentityInvalid, "Invalid service identity",
				"app."+coordinate.name+" must not be blank", FaultStatusInvalidInput)
		}
	}
	return nil
}

// Trimmed returns a copy with every coordinate whitespace-trimmed, so a stray
// overlay space never reaches a resource attribute.
func (a AppIdentity) Trimmed() AppIdentity {
	return AppIdentity{
		Landscape: strings.TrimSpace(a.Landscape),
		Platform:  strings.TrimSpace(a.Platform),
		Service:   strings.TrimSpace(a.Service),
		Module:    strings.TrimSpace(a.Module),
		Version:   strings.TrimSpace(a.Version),
	}
}
