package standardconfig

import (
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

// ProblemVersion is the contract version segment of every standard-config
// problem type URI (C0 §2/D8). Bumping it mints new problem types rather than
// mutating the existing ones.
const ProblemVersion = "v1"

// Standard-config problem ids. Each one is stable and catalogued, and resolves
// its RFC 9457 type URI through the single-source builder in the
// errors-problems sibling, so a consumer classifies an infra-configuration
// failure without any standard-config-specific knowledge.
const (
	// ProblemConnectionUnknown reports a lookup for a named connection that the
	// resolved block does not declare — a typo in code or a missing YAML entry.
	ProblemConnectionUnknown = "connection-unknown"
	// ProblemConnectionAmbiguous reports a lookup that matches more than one
	// declared connection once case is ignored, so no single answer is right.
	ProblemConnectionAmbiguous = "connection-ambiguous"
	// ProblemConnectionKeyInvalid reports a connection name that is not an
	// identifier and therefore has no reachable environment override path.
	// JSON Schema cannot enforce this because the config library matches keys
	// canonically and rejects key-spelling constraints as authoring faults.
	ProblemConnectionKeyInvalid = "connection-key-invalid"
	// ProblemPresetUnknown reports a request for a preset this library does not
	// ship. The four infra presets are frozen by C0 §3.
	ProblemPresetUnknown = "preset-unknown"
)

// ProblemTypes returns the standard-config problem-type declarations in stable
// order. Consumers register them on their own registry and export them into
// their service catalog so the shipped problems appear in the published error
// portal alongside the service's own.
func ProblemTypes() []problem.Type {
	return []problem.Type{
		presetProblem(ProblemConnectionUnknown, "Named connection not configured"),
		presetProblem(ProblemConnectionAmbiguous, "Named connection is ambiguous"),
		presetProblem(ProblemConnectionKeyInvalid, "Connection name is not an identifier"),
		presetProblem(ProblemPresetUnknown, "Infra preset not shipped"),
	}
}

// presetProblem declares one standard-config problem type at the shared
// contract version, keeping the declarations above free of repetition.
//
// Every problem this library raises is a 500 and none is recoverable, and that
// is a property of the failure class rather than a coincidence: an infra block
// that does not declare the connection a service asked for is a deployment
// mistake, and retrying it changes nothing.
func presetProblem(id string, title string) problem.Type {
	return problem.Type{
		ID:          id,
		Title:       title,
		Version:     ProblemVersion,
		Status:      500,
		Recoverable: false,
	}
}

// Problems mints this library's problem-typed errors from a service's error
// portal.
//
// It is the single place an infra-configuration failure becomes an RFC 9457
// envelope: nothing else here formats a type URI or picks a status code, which
// is what keeps the same failure identical whether it surfaces from a keyed
// lookup, a key-contract check, or a preset lookup.
type Problems struct {
	registry *problem.Registry
}

// NewProblems creates the preset problem factory bound to portal, optionally
// registering a consumer's own problem types alongside this library's.
//
// The portal carries the service's own LPSM identity, so a misconfigured
// connection is attributed to the service that misconfigured it rather than to
// this library. Extra types share one registry with the shipped ones so a
// consumer exports ONE catalog; a type whose id collides with a shipped problem
// is rejected rather than silently shadowing it.
func NewProblems(portal problem.ErrorPortal, extra ...problem.Type) (*Problems, error) {
	registry, err := problem.NewRegistry(portal, append(ProblemTypes(), extra...)...)
	if err != nil {
		return nil, err
	}
	return &Problems{registry: registry}, nil
}

// Registry returns the enumerable registry of the shipped problem types, for a
// consumer composing its own catalog.
func (p *Problems) Registry() *problem.Registry {
	return p.registry
}

// Catalog returns a catalog pre-populated with every type on this registry,
// ready to render Problem CR content (C0 §14).
//
// It deliberately does NOT add the portable generic set: which generics a
// service publishes is the service's decision, and a consumer that wants them
// calls AddGenerics on the returned catalog itself.
func (p *Problems) Catalog() (*problem.Catalog, error) {
	catalog := problem.NewCatalog(p.registry.Portal())
	for _, declared := range p.registry.Entries() {
		if err := catalog.AddType(declared); err != nil {
			return nil, err
		}
	}
	return catalog, nil
}

// Raise builds the problem-typed error registered for id, carrying detail and
// the typed data payload.
//
// It is total: an unregistered id yields an uncatalogued 500 problem rather
// than a second error to handle, because a failure to describe a failure must
// never replace it.
func (p *Problems) Raise(id string, detail string, data map[string]any) error {
	return problem.NewError(p.envelope(id, detail, data))
}

// envelope resolves id into an RFC 9457 envelope through the registry and the
// single-source type-URI builder, degrading to the uncatalogued fallback rather
// than failing.
func (p *Problems) envelope(id string, detail string, data map[string]any) problem.Problem {
	if data == nil {
		data = map[string]any{}
	}
	declared, found := p.registry.Lookup(id)
	if !found {
		return p.uncatalogued(detail, data)
	}
	uri, err := p.registry.TypeURIFor(declared)
	if err != nil {
		return p.uncatalogued(detail, data)
	}
	return problem.Problem{
		Type:        uri,
		Title:       declared.Title,
		Status:      declared.Status,
		Detail:      &detail,
		Recoverable: declared.Recoverable,
		Data:        data,
	}
}

// uncatalogued produces the C0 §14 uncatalogued fallback: an unknown id or an
// unbuildable type URI is a misconfiguration on the consumer's side, and the
// original failure still has to reach the caller.
func (p *Problems) uncatalogued(detail string, data map[string]any) problem.Problem {
	fallback := problem.FromObject(nil, problem.TransformOptions{
		Portal:         p.registry.Portal(),
		DefaultStatus:  500,
		DefaultVersion: ProblemVersion,
	})
	fallback.Detail = &detail
	fallback.Data = data
	return fallback
}
