package e2e

import (
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

// ProblemVersion is the contract version segment of every harness problem type
// URI (C0 §2/D8). Bumping it mints new problem types rather than mutating the
// existing ones.
const ProblemVersion = "v1"

// Harness problem ids. Every id is stable, catalogued, and resolves its RFC
// 9457 `type` URI through the single-source builder in the errors-problems
// sibling, so a harness failure is classifiable without any e2e-specific
// knowledge.
//
// These describe failures of the HARNESS or of the journey it is running. A
// problem the system under test itself returned is never re-minted here.
const (
	// ProblemDriverUnconfigured reports a driver constructed without a seam it
	// cannot substitute for, e.g. a compiled driver with no artifact path.
	ProblemDriverUnconfigured = "driver-unconfigured"
	// ProblemArtifactMissing reports a compiled artifact that is absent from the
	// filesystem, so the driver refuses to run rather than reporting a shell's
	// "not found" as a journey failure.
	ProblemArtifactMissing = "artifact-missing"
	// ProblemInvocationFailed reports an invocation the driver could not carry
	// out at all — the process never started, or the entrypoint panicked into an
	// error before producing an exit code.
	ProblemInvocationFailed = "invocation-failed"
	// ProblemJourneyEmpty reports a journey with no steps, which would otherwise
	// pass vacuously and record a green that proves nothing.
	ProblemJourneyEmpty = "journey-empty"
	// ProblemStepFailed reports a step whose observed result missed its
	// expectation, carrying the step name, the wanted and observed exit codes,
	// and the missing output fragments as typed data.
	ProblemStepFailed = "step-failed"
	// ProblemParityMismatch reports two reports for the same journey that
	// disagree, i.e. the compiled artifact and the in-process run behaved
	// differently.
	ProblemParityMismatch = "driver-parity-mismatch"
	// ProblemTargetIncomplete reports a Garden preview target that is missing a
	// setting the harness cannot invent, e.g. a blank base URL.
	ProblemTargetIncomplete = "preview-target-incomplete"
	// ProblemTargetUnreadable reports an environment the harness could not read
	// through its [interfaces.System] seam at all.
	ProblemTargetUnreadable = "preview-target-unreadable"
	// ProblemFixtureInvalid reports a fixture the harness refuses to emit, e.g.
	// a blank block key or a landscape overlay with no landscape.
	ProblemFixtureInvalid = "fixture-invalid"
	// ProblemFixtureUnwritable reports a fixture that could not be materialized
	// onto the filesystem seam.
	ProblemFixtureUnwritable = "fixture-unwritable"
)

// ProblemTypes returns the harness problem-type declarations in stable order.
// Consumers register them on their own registry and export them into their
// service catalog so the shipped problems appear in the published error portal
// alongside the service's own.
func ProblemTypes() []problem.Type {
	return []problem.Type{
		harnessProblem(ProblemDriverUnconfigured, "Harness driver unconfigured", 500, false),
		harnessProblem(ProblemArtifactMissing, "Compiled artifact missing", 500, false),
		harnessProblem(ProblemInvocationFailed, "Harness invocation failed", 500, true),
		harnessProblem(ProblemJourneyEmpty, "Journey has no steps", 422, false),
		harnessProblem(ProblemStepFailed, "Journey step failed", 422, false),
		harnessProblem(ProblemParityMismatch, "Drivers disagree on the journey", 422, false),
		harnessProblem(ProblemTargetIncomplete, "Preview target incomplete", 422, false),
		harnessProblem(ProblemTargetUnreadable, "Preview environment unreadable", 500, true),
		harnessProblem(ProblemFixtureInvalid, "Fixture invalid", 422, false),
		harnessProblem(ProblemFixtureUnwritable, "Fixture could not be written", 500, true),
	}
}

// harnessProblem declares one harness problem type at the shared contract
// version, keeping the declarations above free of repetition.
func harnessProblem(id string, title string, status int, recoverable bool) problem.Type {
	return problem.Type{
		ID:          id,
		Title:       title,
		Version:     ProblemVersion,
		Status:      status,
		Recoverable: recoverable,
	}
}

// Problems mints the harness's problem-typed errors from a service's error
// portal.
//
// It is the single place a harness failure becomes an RFC 9457 envelope: no
// driver, journey, target, or fixture formats a type URI or picks a status code
// itself, which is what keeps the same failure identical wherever it surfaces.
type Problems struct {
	registry *problem.Registry
}

// NewProblems creates the harness problem factory bound to portal, optionally
// registering a consumer's own problem types alongside the harness's.
//
// The portal carries the service's own LPSM identity, so a journey failure
// raised inside a consumer's suite is attributed to that consumer rather than to
// this library. Extra types share one registry with the harness's so a consumer
// exports ONE catalog; an id that collides with a harness problem is rejected
// rather than silently shadowing it.
func NewProblems(portal problem.ErrorPortal, extra ...problem.Type) (*Problems, error) {
	registry, err := problem.NewRegistry(portal, append(ProblemTypes(), extra...)...)
	if err != nil {
		return nil, err
	}
	return &Problems{registry: registry}, nil
}

// Registry returns the enumerable registry of the harness problem types, for a
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
