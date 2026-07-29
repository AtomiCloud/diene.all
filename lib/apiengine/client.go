package apiengine

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

// Doer is the outbound HTTP seam.
//
// [http.Client] satisfies it, and so does any test double, which is why nothing
// in this library constructs a transport of its own: a consumer that needs
// proxying, tracing, or connection tuning binds it here rather than reaching
// into the engine.
type Doer interface {
	Do(request *http.Request) (*http.Response, error)
}

// Request describes one call against a backend.
type Request struct {
	// Method is the HTTP method. Blank means GET.
	Method string
	// Path is the path appended to the backend's base URL, e.g. `/v1/users`.
	Path string
	// Query is the URL query, or nil for none.
	Query url.Values
	// Header carries additional request headers. The engine sets Accept,
	// Content-Type, and Authorization itself.
	Header http.Header
	// Body is JSON-encoded and sent when non-nil.
	Body any
}

// ClientOptions configures one backend's client.
type ClientOptions struct {
	// Backend is the logical backend name, used in problem payloads.
	Backend string
	// Config is that backend's settings.
	Config BackendConfig
	// Doer is the outbound HTTP seam. Required.
	Doer Doer
	// Tokens resolves this backend's credentials. Optional: a backend with no
	// resource indicator needs none.
	//
	// This is the auth-engine seam — a *authengine.TokenCache satisfies it — so
	// the client never learns whether a user session or a client-credentials
	// flow produced the token.
	Tokens authengine.Retriever
	// Resource is the auth-engine resource name tokens are resolved under.
	Resource string
	// Problems mints this client's problem-typed errors. Required.
	Problems *Problems
	// Retry is the resilience profile.
	Retry RetryConfig
	// Sleep waits before the single retry. Defaults to [time.Sleep]; tests
	// inject their own so a retry costs no wall-clock time.
	Sleep func(time.Duration)
}

// Client is one backend's HTTP client.
//
// It is safe for concurrent use: every field is set once at construction and the
// per-call state lives on the stack.
type Client struct {
	backend  string
	base     string
	config   BackendConfig
	doer     Doer
	tokens   authengine.Retriever
	resource string
	problems *Problems
	retry    RetryConfig
	sleep    func(time.Duration)
}

// errUnconfigured reports a call made without the dependency every other
// failure is expressed through. It is a plain error by necessity: there is no
// factory available to raise a problem-typed one.
func errUnconfigured(component string) error {
	return errors.New("api-engine " + component + " is not configured")
}

// NewClient creates the client for one backend.
func NewClient(options ClientOptions) (*Client, error) {
	if options.Problems == nil {
		return nil, errUnconfigured("client")
	}
	if options.Doer == nil {
		return nil, options.Problems.Raise(ProblemConfigInvalid,
			"a client was created without an HTTP doer",
			map[string]any{"backend": options.Backend})
	}
	base := strings.TrimSuffix(strings.TrimSpace(options.Config.BaseURL), "/")
	if base == "" {
		return nil, options.Problems.Raise(ProblemConfigInvalid,
			"a client was created without a base URL",
			map[string]any{"backend": options.Backend})
	}
	// Parse the origin once, here, so a malformed host is a construction
	// failure rather than a surprise on the first call in production.
	if _, err := url.Parse(base); err != nil {
		return nil, options.Problems.RaiseFrom(ProblemConfigInvalid, err,
			"a client was created with a malformed base URL",
			map[string]any{"backend": options.Backend, "baseUrl": options.Config.BaseURL})
	}

	resource := options.Resource
	if strings.TrimSpace(resource) == "" {
		resource = options.Backend
	}
	sleep := options.Sleep
	if sleep == nil {
		sleep = time.Sleep
	}
	return &Client{
		backend:  options.Backend,
		base:     base,
		config:   options.Config,
		doer:     options.Doer,
		tokens:   options.Tokens,
		resource: resource,
		problems: options.Problems,
		retry:    options.Retry,
		sleep:    sleep,
	}, nil
}

// Backend returns the logical backend name this client calls.
func (c *Client) Backend() string { return c.backend }

// BaseURL returns the backend's origin with any trailing slash removed.
func (c *Client) BaseURL() string { return c.base }

// Response is one classified HTTP response.
//
// It is what [Client.Call] returns and what [Execute] decodes: the raw material
// for callers that need the status or headers, without every call site
// re-running the classification.
type Response struct {
	// Outcome is the 3-case classification.
	Outcome Outcome
	// Status is the HTTP status, or 0 when the round trip never completed.
	Status int
	// Header is the response header, nil when the round trip never completed.
	Header http.Header
	// Body is the response body, already read.
	Body []byte
}

// Call performs the request and classifies the result, applying the
// retry-once-on-network-error profile.
//
// It returns an error only for a failure that produced no response at all —
// a request that would not build, credentials that would not resolve, or a
// transport failure that survived the retry. A 4xx or 5xx is a successful call
// with a non-success outcome, because the caller may want the status.
func (c *Client) Call(ctx context.Context, request Request) (Response, error) {
	// The timeout covers the whole call — both attempts and the body read — so
	// it is cancelled here rather than inside the per-attempt builder, where it
	// would either leak or expire while the caller is still reading.
	callCtx, cancel := context.WithTimeout(ctx, c.config.RequestTimeout())
	defer cancel()

	build := func() (*http.Request, error) { return c.build(callCtx, request) }

	response, transportErr := c.send(build)
	if transportErr != nil {
		var problemErr *problem.Error
		if errors.As(transportErr, &problemErr) {
			return Response{}, transportErr
		}
		return Response{}, c.problems.RaiseFrom(ProblemTransport, transportErr,
			"the request to "+c.backend+" did not complete",
			map[string]any{"backend": c.backend, "path": request.Path})
	}
	defer func() { _ = response.Body.Close() }()

	body, err := io.ReadAll(response.Body)
	if err != nil {
		return Response{}, c.problems.RaiseFrom(ProblemResponseUnreadable, err,
			"the response from "+c.backend+" could not be read",
			map[string]any{
				"backend": c.backend, "path": request.Path,
				"status": response.StatusCode,
			})
	}

	return Response{
		Outcome: Classify(response.StatusCode, nil),
		Status:  response.StatusCode,
		Header:  response.Header,
		Body:    body,
	}, nil
}

// send runs the round trip, retrying exactly once on a transport failure when
// the profile allows it.
//
// The request is rebuilt for the retry rather than reused: a request whose body
// has already been consumed cannot be replayed.
func (c *Client) send(build func() (*http.Request, error)) (*http.Response, error) {
	request, err := build()
	if err != nil {
		return nil, err
	}
	response, transportErr := c.doer.Do(request)
	if transportErr == nil {
		return response, nil
	}
	if !c.retry.Network {
		return nil, transportErr
	}

	if delay := c.retry.Delay.Std(); delay > 0 {
		c.sleep(delay)
	}
	retryRequest, err := build()
	if err != nil {
		return nil, err
	}
	return c.doer.Do(retryRequest)
}

// build assembles the outbound request, attaching this backend's credentials.
func (c *Client) build(ctx context.Context, request Request) (*http.Request, error) {
	target, err := c.resolve(request)
	if err != nil {
		return nil, err
	}

	var body io.Reader
	if request.Body != nil {
		encoded, encodeErr := json.Marshal(request.Body)
		if encodeErr != nil {
			return nil, c.problems.RaiseFrom(ProblemRequestUnbuildable, encodeErr,
				"the request body for "+c.backend+" could not be encoded",
				map[string]any{"backend": c.backend, "path": request.Path})
		}
		body = bytes.NewReader(encoded)
	}

	method := request.Method
	if method == "" {
		method = http.MethodGet
	}
	built, err := http.NewRequestWithContext(ctx, method, target, body)
	if err != nil {
		return nil, c.problems.RaiseFrom(ProblemRequestUnbuildable, err,
			"the request to "+c.backend+" could not be built",
			map[string]any{"backend": c.backend, "method": method, "path": request.Path})
	}

	for name, values := range request.Header {
		for _, value := range values {
			built.Header.Add(name, value)
		}
	}
	built.Header.Set("Accept", "application/json, application/problem+json")
	if request.Body != nil {
		built.Header.Set("Content-Type", "application/json")
	}
	if err := c.authorize(ctx, built); err != nil {
		return nil, err
	}
	return built, nil
}

// resolve joins the request path and query onto the backend's base URL.
func (c *Client) resolve(request Request) (string, error) {
	path := request.Path
	if path != "" && !strings.HasPrefix(path, "/") {
		path = "/" + path
	}
	target, err := url.Parse(c.base + path)
	if err != nil {
		return "", c.problems.RaiseFrom(ProblemRequestUnbuildable, err,
			"the request path for "+c.backend+" is not a valid URL",
			map[string]any{"backend": c.backend, "path": request.Path})
	}
	if len(request.Query) > 0 {
		target.RawQuery = request.Query.Encode()
	}
	return target.String(), nil
}

// authorize attaches this backend's bearer token.
//
// A client with no retriever sends the request unauthenticated: not every
// backend needs credentials, and demanding a token for one that does not would
// force consumers to configure an IdP they never use.
func (c *Client) authorize(ctx context.Context, request *http.Request) error {
	if c.tokens == nil {
		return nil
	}
	token, err := c.tokens.Token(ctx, c.resource)
	if err != nil {
		return c.problems.RaiseFrom(ProblemCredentialsUnavailable, err,
			"credentials for "+c.backend+" could not be resolved",
			map[string]any{"backend": c.backend, "resource": c.resource})
	}
	request.Header.Set("Authorization", "Bearer "+token.Value)
	return nil
}

// Execute performs the request and maps the 3-case classification onto the
// idiomatic Go (T, error) pair.
//
// Success decodes the body into T. A problem surfaces as a *[problem.Error]
// carrying the backend's own envelope — type, title, status, and the `data`
// extension all intact, because that envelope IS the backend's published
// contract and re-minting it would strip the typed payload the caller is
// expecting. A transport case surfaces as an api-engine problem-typed error.
//
// It is a function rather than a method because Go does not permit type
// parameters on methods.
func Execute[T any](ctx context.Context, client *Client, request Request) (T, error) {
	var zero T
	if client == nil {
		return zero, errUnconfigured("execute")
	}

	response, err := client.Call(ctx, request)
	if err != nil {
		return zero, err
	}

	if response.Outcome == OutcomeSuccess {
		var value T
		// A 204, or any 2xx with no body, leaves the caller its zero value
		// rather than failing to decode nothing.
		if len(bytes.TrimSpace(response.Body)) == 0 {
			return value, nil
		}
		if err := json.Unmarshal(response.Body, &value); err != nil {
			return zero, client.problems.RaiseFrom(ProblemResponseUndecodable, err,
				"the response from "+client.backend+" did not decode",
				map[string]any{
					"backend": client.backend, "path": request.Path,
					"status": response.Status,
				})
		}
		return value, nil
	}

	if response.Outcome == OutcomeProblem {
		decoded, ok := DecodeProblem(response.Body)
		if !ok {
			return zero, client.problems.Raise(ProblemResponseNotProblem,
				client.backend+" returned a client-error status without an RFC 9457 envelope",
				map[string]any{
					"backend": client.backend, "path": request.Path,
					"status": response.Status,
				})
		}
		return zero, problem.NewError(decoded)
	}

	// The transport case, and any outcome this build does not recognise: neither
	// produced a value the caller can use, so both surface as the engine's own
	// transport problem rather than as a zero value with a nil error.
	return zero, client.problems.Raise(ProblemTransport,
		client.backend+" did not answer the request",
		map[string]any{
			"backend": client.backend, "path": request.Path,
			"status": response.Status,
		})
}

// Send performs a request whose response body the caller does not need.
//
// It applies the same 3-case classification as [Execute]; only the success case
// differs, discarding the body instead of decoding it.
func Send(ctx context.Context, client *Client, request Request) error {
	_, err := Execute[json.RawMessage](ctx, client, request)
	return err
}
