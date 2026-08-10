package testhelper_test

import (
	"context"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strconv"

	"github.com/AtomiCloud/diene.go-standard-config/testhelper"
	"github.com/testcontainers/testcontainers-go"
)

// The examples below run everywhere, including where no Docker daemon exists,
// by substituting the [testhelper.Runtime] seam. A REAL test leaves
// Options.Runtime nil and gets [testhelper.DockerRuntime] and a real container;
// the container-backed proof of that path lives in the meta tier.

// exampleContainer reports a fixed address and stops without doing anything.
type exampleContainer struct {
	host string
	port int
}

// Host returns the fixed host.
func (c exampleContainer) Host(context.Context) (string, error) { return c.host, nil }

// Port returns the fixed published port.
func (c exampleContainer) Port(context.Context, string) (int, error) { return c.port, nil }

// Terminate is a no-op: nothing was started.
func (exampleContainer) Terminate(context.Context) error { return nil }

// exampleRuntime hands out an [exampleContainer] instead of talking to Docker.
type exampleRuntime struct {
	container exampleContainer
}

// Start returns the prepared container without starting anything.
func (r exampleRuntime) Start(
	context.Context, testcontainers.ContainerRequest,
) (testhelper.Container, error) {
	return r.container, nil
}

// exampleRuntimeAt builds a runtime whose container reports host and port.
func exampleRuntimeAt(host string, port int) testhelper.Runtime {
	return exampleRuntime{container: exampleContainer{host: host, port: port}}
}

// exampleS3 starts an in-process endpoint that accepts the bucket-creation PUT,
// so the storage examples exercise the real signing path without MinIO.
func exampleS3() (host string, port int, stop func()) {
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, _ *http.Request) {
		writer.WriteHeader(http.StatusOK)
	}))
	parsed, err := url.Parse(server.URL)
	if err != nil {
		panic(err)
	}
	number, err := strconv.Atoi(parsed.Port())
	if err != nil {
		panic(err)
	}
	return parsed.Hostname(), number, server.Close
}
