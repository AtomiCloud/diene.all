package apiengine

import (
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

// ProblemVersion is the contract version segment of every api-engine problem
// type URI (C0 §2/D8). Bumping it mints new problem types rather than mutating
// the existing ones.
const ProblemVersion = "v1"

// Api-engine problem ids. Every id is stable, catalogued, and resolves its RFC
// 9457 `type` URI through the single-source builder in the errors-problems
// sibling, so a client failure is classifiable by a caller without any
// api-engine-specific knowledge.
//
// These describe failures the CLIENT observes. A problem the BACKEND returned
// is not re-minted here: it is decoded and surfaced with the backend's own type,
// title, status, and `data` intact, because rewriting it would destroy the
// contract the backend published.
const (
	// ProblemTransport reports a request that never produced a usable response —
	// a dial, TLS, or read failure, or a 5xx — after the single permitted retry.
	ProblemTransport = "transport-failed"
	// ProblemResponseUnreadable reports a response whose body could not be read
	// off the wire, i.e. a connection that died mid-stream.
	ProblemResponseUnreadable = "response-unreadable"
	// ProblemResponseUndecodable reports a 2xx body that did not decode into the
	// type the caller asked for.
	ProblemResponseUndecodable = "response-undecodable"
	// ProblemResponseNotProblem reports a 4xx that did not carry an RFC 9457
	// envelope, which means the backend is not C0-conformant on that path.
	ProblemResponseNotProblem = "response-not-problem"
	// ProblemBackendUnregistered reports a backend name absent from the client
	// tree, i.e. a call to a backend the consumer never registered.
	ProblemBackendUnregistered = "backend-unregistered"
	// ProblemRequestUnbuildable reports a request that could not be built, e.g. a
	// body that will not encode or a path that will not join onto the base URL.
	ProblemRequestUnbuildable = "request-unbuildable"
	// ProblemCredentialsUnavailable reports a per-backend token the auth-engine
	// retriever could not resolve, so the request was never sent.
	ProblemCredentialsUnavailable = "credentials-unavailable"
	// ProblemConfigInvalid reports an engine configuration the library refuses to
	// start from, e.g. a blank base URL or a duplicate backend name.
	ProblemConfigInvalid = "config-invalid"
)

// ProblemTypes returns the api-engine's problem-type declarations in stable
// order. Consumers register them on their own registry and export them into
// their service catalog so the shipped problems appear in the published error
// portal alongside the service's own.
func ProblemTypes() []problem.Type {
	return []problem.Type{
		apiProblem(ProblemTransport, "Backend transport failed", 502, true),
		apiProblem(ProblemResponseUnreadable, "Backend response unreadable", 502, true),
		apiProblem(ProblemResponseUndecodable, "Backend response undecodable", 502, false),
		apiProblem(ProblemResponseNotProblem, "Backend error was not a problem envelope", 502, false),
		apiProblem(ProblemBackendUnregistered, "Backend not registered", 500, false),
		apiProblem(ProblemRequestUnbuildable, "Request could not be built", 500, false),
		apiProblem(ProblemCredentialsUnavailable, "Backend credentials unavailable", 502, true),
		apiProblem(ProblemConfigInvalid, "Api configuration invalid", 500, false),
	}
}

// apiProblem declares one api-engine problem type at the shared contract
// version, keeping the declarations above free of repetition.
func apiProblem(id string, title string, status int, recoverable bool) problem.Type {
	return problem.Type{
		ID:          id,
		Title:       title,
		Version:     ProblemVersion,
		Status:      status,
		Recoverable: recoverable,
	}
}

// Problems mints the engine's problem-typed errors from a service's error
// portal.
//
// It is the single place a client failure becomes an RFC 9457 envelope: no
// other part of this library formats a type URI or picks a status code, which is
// what keeps the same failure identical whether it surfaces from the client, the
// classifier, or the client tree.
type Problems struct {
	registry *problem.Registry
}

// NewProblems creates the engine's problem factory bound to portal, optionally
// registering a consumer's own problem types alongside the engine's.
//
// The portal carries the service's own LPSM identity, so a transport failure
// raised inside a consumer is attributed to that consumer's error portal rather
// than to this library. Extra types share one registry with the engine's so a
// consumer exports ONE catalog; a type whose id collides with an engine problem
// is rejected rather than silently shadowing it.
func NewProblems(portal problem.ErrorPortal, extra ...problem.Type) (*Problems, error) {
	registry, err := problem.NewRegistry(portal, append(ProblemTypes(), extra...)...)
	if err != nil {
		return nil, err
	}
	return &Problems{registry: registry}, nil
}

// Registry returns the enumerable registry of the engine's problem types, for a
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
// It is total: an unregistered id yields an uncatalogued 500 problem rather than
// a second error to handle, because a failure to describe a failure must never
// replace it.
func (p *Problems) Raise(id string, detail string, data map[string]any) error {
	return problem.NewError(p.envelope(id, detail, data))
}

// RaiseFrom builds the problem-typed error registered for id wrapping cause, so
// errors.Is and errors.As still traverse into the underlying failure.
func (p *Problems) RaiseFrom(id string, cause error, detail string, data map[string]any) error {
	return problem.WrapError(p.envelope(id, detail, data), cause)
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
