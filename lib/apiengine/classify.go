package apiengine

import (
	"encoding/json"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

// Outcome is the 3-case classification every response falls into.
//
// Three cases, not more: a caller only ever needs to know whether it got its
// value, whether the backend refused with a reason it published, or whether the
// call did not complete. Collapsing the last two would lose the difference
// between "you asked for something invalid" and "try again later", and splitting
// them further would push HTTP status handling into every call site.
type Outcome int

const (
	// OutcomeSuccess is a 2xx: the body carries the caller's value.
	OutcomeSuccess Outcome = iota
	// OutcomeProblem is a 4xx: the backend refused and published an RFC 9457
	// envelope saying why. The envelope is the contract, so it reaches the caller
	// unmodified.
	OutcomeProblem
	// OutcomeTransport is a 5xx or a transport failure: the call did not
	// complete. C0 groups them because they are indistinguishable to the caller —
	// in both cases the backend never gave an answer it stands behind.
	OutcomeTransport
)

// String returns the outcome's name.
func (o Outcome) String() string {
	switch o {
	case OutcomeSuccess:
		return "success"
	case OutcomeProblem:
		return "problem"
	case OutcomeTransport:
		return "transport"
	default:
		return "unknown"
	}
}

// Classify performs the 3-case classification.
//
// A transport error wins outright: when the round trip failed there is no
// status to read. Otherwise 2xx is success, 4xx is a problem, and everything
// else — 5xx, and any status outside the three ranges — is transport, because a
// response the client cannot interpret is one the backend did not answer with.
func Classify(status int, transportErr error) Outcome {
	switch {
	case transportErr != nil:
		return OutcomeTransport
	case status >= 200 && status <= 299:
		return OutcomeSuccess
	case status >= 400 && status <= 499:
		return OutcomeProblem
	default:
		return OutcomeTransport
	}
}

// DecodeProblem reads an RFC 9457 envelope out of a 4xx response body.
//
// It reports ok=false for a body that is not a problem envelope rather than
// inventing one, so the caller can raise [ProblemResponseNotProblem] and name
// the non-conformant backend instead of surfacing a plausible-looking envelope
// nobody published. A decoded envelope keeps its `data` extension verbatim,
// which is what carries the backend's typed payload through to the caller.
func DecodeProblem(body []byte) (problem.Problem, bool) {
	// The envelope's own decoder runs first: it rejects anything that is not a
	// JSON object — an array, a bare number, a truncated body — but is
	// deliberately lenient about member types so a slightly-off envelope still
	// reaches a consumer.
	var decoded problem.Problem
	if err := json.Unmarshal(body, &decoded); err != nil {
		return problem.Problem{}, false
	}

	// This client is stricter, because it has to decide whether the backend
	// published a contract at all. A `status` that is not a number, or a `type`
	// that is not a string, means the body is not the envelope it resembles.
	var probe struct {
		Type   *string `json:"type"`
		Title  *string `json:"title"`
		Status *int    `json:"status"`
	}
	if err := json.Unmarshal(body, &probe); err != nil {
		return problem.Problem{}, false
	}
	// RFC 9457 requires `type` and `title`; a body carrying neither is some
	// other JSON document that happens to have parsed.
	if probe.Type == nil && probe.Title == nil {
		return problem.Problem{}, false
	}
	return decoded, true
}
