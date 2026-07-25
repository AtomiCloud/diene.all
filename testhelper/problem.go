package testhelper

import (
	"net/http"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

// ProblemOptions describes a canned RFC 9457 envelope.
type ProblemOptions struct {
	// Type is the problem type URI.
	Type string
	// Title is the short human-readable summary.
	Title string
	// Status is the origin-generated HTTP status.
	Status int
	// Detail is the occurrence-specific explanation, omitted when blank.
	Detail string
	// Instance is the occurrence URI, omitted when blank.
	Instance string
	// Recoverable is the C0 retry-vs-fatal flag.
	Recoverable bool
	// Data is the typed payload extension. This is the member that must survive
	// the whole journey to the caller, so tests set it and assert it.
	Data map[string]any
}

// ProblemResponse builds the canned envelope a fake backend returns.
//
// It is the fixture the 3-case classification is proven against: a client gets
// a problem case only because a body like this came back, so producing one has
// to be a single call rather than a hand-written JSON literal per test.
func ProblemResponse(options ProblemOptions) problem.Problem {
	built := problem.Problem{
		Type:        options.Type,
		Title:       options.Title,
		Status:      options.Status,
		Recoverable: options.Recoverable,
		Data:        options.Data,
	}
	if options.Detail != "" {
		detail := options.Detail
		built.Detail = &detail
	}
	if options.Instance != "" {
		instance := options.Instance
		built.Instance = &instance
	}
	if built.Data == nil {
		built.Data = map[string]any{}
	}
	return built
}

// Canned returns a [Route] serving the envelope with the problem's own status
// and the `application/problem+json` content type RFC 9457 requires.
func Canned(options ProblemOptions) Route {
	envelope := ProblemResponse(options)
	header := http.Header{}
	header.Set("Content-Type", "application/problem+json")
	return Route{Status: envelope.Status, Body: envelope, Header: header}
}
