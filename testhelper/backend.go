package testhelper

import (
	"encoding/json"
	"io"
	"maps"
	"net/http"
	"net/http/httptest"
	"sync"

	"github.com/AtomiCloud/diene.go-api-engine/lib/apiengine"
)

// Route is one canned answer a [FakeBackend] gives.
type Route struct {
	// Status is the HTTP status to return.
	Status int
	// Body is the response body. A []byte or string is sent verbatim; anything
	// else is JSON-encoded.
	Body any
	// Header carries additional response headers.
	Header http.Header
}

// FakeBackend is an in-process HTTP backend for client-tree tests.
//
// It answers by path, records every request it received, and can be told to
// fail the transport a fixed number of times — which is what makes the
// retry-once profile testable without a real network to break.
type FakeBackend struct {
	server *httptest.Server

	mu       sync.Mutex
	routes   map[string]Route
	fallback Route
	requests []RecordedRequest
	failures int
}

// RecordedRequest is one request a [FakeBackend] received.
type RecordedRequest struct {
	// Method is the HTTP method.
	Method string
	// Path is the request path.
	Path string
	// Query is the raw query string.
	Query string
	// Header is the request header, including any Authorization the engine
	// attached.
	Header http.Header
	// Body is the request body as received.
	Body []byte
}

// Authorization returns the request's Authorization header.
func (r RecordedRequest) Authorization() string {
	return r.Header.Get("Authorization")
}

// FakeBackendOptions configures a [FakeBackend].
type FakeBackendOptions struct {
	// Routes maps a request path to the answer for it.
	Routes map[string]Route
	// Fallback answers a path with no route. Defaults to 404 with an RFC 9457
	// envelope, because a real C0-conformant backend does not answer a miss
	// with a bare status.
	Fallback *Route
	// TransportFailures is how many leading requests die before a response is
	// produced. One failure exercises the single retry; two exhaust it.
	TransportFailures int
}

// NewFakeBackend starts a fake backend. Close it with [FakeBackend.Close].
func NewFakeBackend(options FakeBackendOptions) *FakeBackend {
	routes := make(map[string]Route, len(options.Routes))
	maps.Copy(routes, options.Routes)

	fallback := Route{Status: http.StatusNotFound, Body: ProblemResponse(ProblemOptions{
		Type:   "https://local.atomi.cloud/docs/local/go/app/core/v1/entity-not-found",
		Title:  "Entity not found",
		Status: http.StatusNotFound,
	})}
	if options.Fallback != nil {
		fallback = *options.Fallback
	}

	backend := &FakeBackend{
		routes:   routes,
		fallback: fallback,
		failures: options.TransportFailures,
	}
	backend.server = httptest.NewServer(http.HandlerFunc(backend.serve))
	return backend
}

// serve answers one request, recording it first.
func (b *FakeBackend) serve(writer http.ResponseWriter, request *http.Request) {
	// net/http guarantees a non-nil Body on a server request, and a body that
	// died mid-read is worth recording as far as it got — a test asserting on a
	// truncated request wants the truncation, not nothing.
	body, _ := io.ReadAll(request.Body)

	b.mu.Lock()
	b.requests = append(b.requests, RecordedRequest{
		Method: request.Method,
		Path:   request.URL.Path,
		Query:  request.URL.RawQuery,
		Header: request.Header.Clone(),
		Body:   body,
	})
	failing := b.failures > 0
	if failing {
		b.failures--
	}
	route, found := b.routes[request.URL.Path]
	if !found {
		route = b.fallback
	}
	b.mu.Unlock()

	if failing {
		// Hijack and drop the connection: this is the closest in-process
		// equivalent of a peer that vanishes mid-request, which is exactly the
		// failure the retry-once profile exists for.
		hijacker, ok := writer.(http.Hijacker)
		if ok {
			connection, _, err := hijacker.Hijack()
			if err == nil {
				_ = connection.Close()
				return
			}
		}
	}

	for name, values := range route.Header {
		for _, value := range values {
			writer.Header().Add(name, value)
		}
	}
	payload, contentType := encodeBody(route.Body)
	if contentType != "" && writer.Header().Get("Content-Type") == "" {
		writer.Header().Set("Content-Type", contentType)
	}
	status := route.Status
	if status == 0 {
		status = http.StatusOK
	}
	writer.WriteHeader(status)
	_, _ = writer.Write(payload)
}

// encodeBody renders a route body and reports the content type it implies.
func encodeBody(body any) ([]byte, string) {
	switch typed := body.(type) {
	case nil:
		return nil, ""
	case []byte:
		return typed, ""
	case string:
		return []byte(typed), ""
	default:
		encoded, err := json.Marshal(typed)
		if err != nil {
			// A fixture that will not encode is a test-authoring mistake, and
			// surfacing it as a 500-shaped body is more use than panicking
			// inside a server goroutine where the stack means nothing.
			return []byte(`{"error":"testhelper: route body did not encode"}`), "application/json"
		}
		return encoded, "application/json"
	}
}

// URL returns the backend's base URL.
func (b *FakeBackend) URL() string { return b.server.URL }

// Close shuts the backend down.
func (b *FakeBackend) Close() { b.server.Close() }

// Requests returns the requests received so far, oldest first.
func (b *FakeBackend) Requests() []RecordedRequest {
	b.mu.Lock()
	defer b.mu.Unlock()
	out := make([]RecordedRequest, len(b.requests))
	copy(out, b.requests)
	return out
}

// Count returns how many requests the backend received.
//
// It is the assertion the retry profile is proven with: one call that succeeds
// after a single transport failure must leave a count of exactly two.
func (b *FakeBackend) Count() int {
	b.mu.Lock()
	defer b.mu.Unlock()
	return len(b.requests)
}

// SetRoute adds or replaces a route while the backend is running.
func (b *FakeBackend) SetRoute(path string, route Route) {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.routes[path] = route
}

// Backend returns the engine config block entry pointing at this fake.
func (b *FakeBackend) Backend() apiengine.BackendConfig {
	return apiengine.BackendConfig{BaseURL: b.URL()}
}
