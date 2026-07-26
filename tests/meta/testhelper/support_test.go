package testhelper_test

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"testing"

	"github.com/AtomiCloud/diene.go-e2e/lib/e2e"
	"github.com/AtomiCloud/diene.go-e2e/testhelper"
	"github.com/testcontainers/testcontainers-go"
)

// The meta tier's subject is the TestHelper itself. Every assertion helper is
// proven twice — it passes on known-good input and FAILS on known-bad — because
// an assertion that cannot fail is worse than no assertion: it turns a suite
// green while proving nothing.

// recorder is the [testhelper.TestingT] the assertions are pointed at so their
// failures can be observed instead of ending the test.
type recorder struct {
	helped  int
	failed  bool
	message string
}

// Helper records that the assertion marked itself.
func (r *recorder) Helper() {
	r.helped++
}

// Fatalf records the failure instead of aborting.
func (r *recorder) Fatalf(format string, args ...any) {
	r.failed = true
	r.message = fmt.Sprintf(format, args...)
}

// errBoom is the arbitrary underlying failure the fakes are made to return.
var errBoom = errors.New("boom")

// requireProblems builds the harness problem factory or fails the test.
func requireProblems(t *testing.T) *e2e.Problems {
	t.Helper()
	problems, err := testhelper.SampleProblems()
	if err != nil {
		t.Fatalf("SampleProblems() error = %v", err)
	}
	return problems
}

// expectPass asserts the helper accepted its input and still marked itself.
func expectPass(t *testing.T, observed *recorder) {
	t.Helper()
	if observed.failed {
		t.Fatalf("helper failed on known-good input: %s", observed.message)
	}
	if observed.helped == 0 {
		t.Fatal("helper did not mark itself with Helper()")
	}
}

// expectFail asserts the helper rejected its input and said why.
func expectFail(t *testing.T, observed *recorder, fragment string) {
	t.Helper()
	if !observed.failed {
		t.Fatal("helper passed on known-bad input")
	}
	if !strings.Contains(observed.message, fragment) {
		t.Fatalf("helper said %q, want it to mention %q", observed.message, fragment)
	}
	if observed.helped == 0 {
		t.Fatal("helper did not mark itself with Helper()")
	}
}

// fakeContainer is a started container that never touches Docker.
type fakeContainer struct {
	host         string
	port         int
	hostErr      error
	portErr      error
	terminateAt  *int
	terminateErr error
}

// Host reports the container's address.
func (c *fakeContainer) Host(context.Context) (string, error) {
	return c.host, c.hostErr
}

// Port reports the published port.
func (c *fakeContainer) Port(context.Context, string) (int, error) {
	return c.port, c.portErr
}

// Terminate records that it was asked to stop.
func (c *fakeContainer) Terminate(context.Context) error {
	if c.terminateAt != nil {
		*c.terminateAt++
	}
	return c.terminateErr
}

// fakeRuntime hands out fake containers in order, so a stack can be booted and
// unwound without Docker.
type fakeRuntime struct {
	containers []testhelper.PresetContainer
	failures   []error
	started    int
}

// Start returns the next scripted container or failure.
func (r *fakeRuntime) Start(context.Context, testcontainers.ContainerRequest) (testhelper.PresetContainer, error) {
	index := r.started
	r.started++
	if index < len(r.failures) && r.failures[index] != nil {
		return nil, r.failures[index]
	}
	if index < len(r.containers) {
		return r.containers[index], nil
	}
	return &fakeContainer{host: "127.0.0.1", port: 15432}, nil
}
