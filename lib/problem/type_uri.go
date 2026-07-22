package problem

import (
	"strconv"
	"strings"
)

// ErrorPortal is the service-tree config block the problem type-URI template is
// fed from (C0 §2). The LPSM segments (Landscape/Platform/Service/Module) are
// the declaring identity that also derives public hostnames, so a type URI is
// stable, addressable, and never hand-authored per row.
//
// Real services supply their build-time portal (sourced from config, never
// hardcoded per R4); [LocalErrorPortal] is the fallback for client-local errors
// that have no backend context.
type ErrorPortal struct {
	// Scheme is the URI scheme, conventionally `https`.
	Scheme string
	// Host serves the problem docs, e.g. docs.raichu.cluster.atomi.cloud.
	Host string
	// Landscape is the LPSM `L` segment.
	Landscape string
	// Platform is the LPSM `P` segment.
	Platform string
	// Service is the LPSM `S` segment.
	Service string
	// Module is the LPSM `M` segment.
	Module string
}

// LocalErrorPortal is the default portal for client-local errors with no
// service backend context (e.g. a crash before any backend is known). Real
// programs pass their build-time LPSM portal instead; this keeps the single
// builder usable in isolation and in tests.
func LocalErrorPortal() ErrorPortal {
	return ErrorPortal{
		Scheme:    "https",
		Host:      "local.atomi.cloud",
		Landscape: "local",
		Platform:  "go",
		Service:   "app",
		Module:    "core",
	}
}

// InvalidSegmentError reports a problem type-URI segment that is empty or
// contains a `/`. Validating segments at the boundary keeps the URI canonical
// and catches misconfigured portals instead of producing a malformed URI.
type InvalidSegmentError struct {
	// Name is the offending segment name (e.g. "host", "id").
	Name string
	// Value is the rejected segment value.
	Value string
}

// Error implements the error interface.
func (e *InvalidSegmentError) Error() string {
	return "problem type URI segment " + e.Name + " must be a non-empty single path segment, got " + strconv.Quote(e.Value)
}

// TypeURI builds the RFC 9457 `type` URI from an [ErrorPortal] block.
//
// This is the single source of the C0 §2 template
// `{scheme}://{host}/docs/{landscape}/{platform}/{service}/{module}/{version}/{id}`.
// Every problem — catalog entries, runtime envelopes, local errors — resolves
// its `type` through this function. Each segment must be a non-empty single
// path segment; otherwise an [InvalidSegmentError] is returned.
func TypeURI(portal ErrorPortal, version, id string) (string, error) {
	segments := [...]struct {
		name  string
		value string
	}{
		{"scheme", portal.Scheme},
		{"host", portal.Host},
		{"landscape", portal.Landscape},
		{"platform", portal.Platform},
		{"service", portal.Service},
		{"module", portal.Module},
		{"version", version},
		{"id", id},
	}
	for _, segment := range segments {
		if segment.value == "" || strings.Contains(segment.value, "/") {
			return "", &InvalidSegmentError{Name: segment.name, Value: segment.value}
		}
	}
	return portal.Scheme + "://" + portal.Host + "/docs/" +
		portal.Landscape + "/" + portal.Platform + "/" + portal.Service + "/" +
		portal.Module + "/" + version + "/" + id, nil
}
