package testhelper_test

import (
	"context"
	"errors"
	"fmt"
	"testing"

	"github.com/AtomiCloud/diene.go-config/lib/config"
	"github.com/AtomiCloud/diene.go-standard-config/lib/standardconfig"
	"github.com/AtomiCloud/diene.go-standard-config/testhelper"
	"github.com/testcontainers/testcontainers-go"
)

// errStub is the failure a stub runtime or container reports.
var errStub = errors.New("stub failure")

// recorder is the double the assert-the-asserter suite drives the helpers with.
// It satisfies testhelper.TestingT without ending the goroutine, so a helper's
// failure path is observable instead of fatal.
type recorder struct {
	helped   int
	failures []string
}

// Helper records that the assertion marked itself as a helper.
func (r *recorder) Helper() { r.helped++ }

// Fatalf records a failure instead of ending the test.
func (r *recorder) Fatalf(format string, args ...any) {
	r.failures = append(r.failures, fmt.Sprintf(format, args...))
}

// failed reports whether the helper under test raised a failure.
func (r *recorder) failed() bool { return len(r.failures) > 0 }

// only returns the single recorded failure, failing the surrounding test when
// the count is not exactly one.
func (r *recorder) only(t *testing.T) string {
	t.Helper()
	if len(r.failures) != 1 {
		t.Fatalf("expected exactly one failure, got %d: %v", len(r.failures), r.failures)
	}
	return r.failures[0]
}

// stubContainer is a container that never talks to Docker. Each field decides
// whether the corresponding call succeeds.
type stubContainer struct {
	host          string
	port          int
	hostErr       error
	portErr       error
	terminateErr  error
	terminateSeen *int
}

// Host returns the stubbed host or its stubbed failure.
func (s *stubContainer) Host(context.Context) (string, error) {
	if s.hostErr != nil {
		return "", s.hostErr
	}
	return s.host, nil
}

// Port returns the stubbed published port or its stubbed failure.
func (s *stubContainer) Port(context.Context, string) (int, error) {
	if s.portErr != nil {
		return 0, s.portErr
	}
	return s.port, nil
}

// Terminate records the call and returns its stubbed result.
func (s *stubContainer) Terminate(context.Context) error {
	if s.terminateSeen != nil {
		*s.terminateSeen++
	}
	return s.terminateErr
}

// stubRuntime hands out a prepared container, or fails the start outright.
type stubRuntime struct {
	container  testhelper.Container
	startErr   error
	requests   []testcontainers.ContainerRequest
	startCount int
}

// Start records the request and returns the prepared outcome.
func (s *stubRuntime) Start(
	_ context.Context, request testcontainers.ContainerRequest,
) (testhelper.Container, error) {
	s.startCount++
	s.requests = append(s.requests, request)
	if s.startErr != nil {
		return nil, s.startErr
	}
	return s.container, nil
}

// okRuntime is a stub runtime that starts successfully on a fixed address.
func okRuntime(host string, port int, terminations *int) *stubRuntime {
	return &stubRuntime{container: &stubContainer{host: host, port: port, terminateSeen: terminations}}
}

// presetSchema composes a one-block root schema for a preset, so an emitted
// block can be validated against the exact fragment the library publishes.
func presetSchema(t *testing.T, blockKey string) config.Schema {
	t.Helper()
	fragment, ok := standardconfig.Schemas()[blockKey]
	if !ok {
		t.Fatalf("no shipped preset under %q", blockKey)
	}
	return config.ComposeSchema(config.NewBlock(blockKey, true, fragment))
}

// requireBlockValid fails the test unless an emitted block validates against
// its own preset schema. It round-trips through the shipped struct tags so the
// assertion covers the Go type and the JSON Schema agreeing, not just the map.
func requireBlockValid(t *testing.T, blockKey string, block any) {
	t.Helper()
	instance, err := jsonRoundTrip(blockKey, block)
	if err != nil {
		t.Fatalf("re-encode %s block: %v", blockKey, err)
	}
	if err := presetSchema(t, blockKey).Validate(instance); err != nil {
		t.Fatalf("%s block is not valid against its own preset schema: %v", blockKey, err)
	}
}

// newRequest builds a minimal container request for the runtime-level tests.
func newRequest(image string) testcontainers.ContainerRequest {
	return testcontainers.ContainerRequest{Image: image}
}
