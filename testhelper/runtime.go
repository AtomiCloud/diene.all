package testhelper

import (
	"context"

	"github.com/testcontainers/testcontainers-go"
)

// Container is the subset of a started container the preset glue uses: where it
// listens, and how to stop it.
//
// Keeping the surface this small is what lets a test substitute the whole
// container runtime with a few lines, and it keeps the glue honest — a start
// helper that needed more of a container than an address would be doing
// something other than emitting a config block.
type Container interface {
	// Host returns the address the container is reachable at from the test.
	Host(ctx context.Context) (string, error)
	// Port maps an in-container port spec such as "5432/tcp" to the host port
	// it was published on.
	Port(ctx context.Context, spec string) (int, error)
	// Terminate stops and removes the container.
	Terminate(ctx context.Context) error
}

// Runtime starts containers for the preset glue.
//
// It is the determinism seam: the default [DockerRuntime] talks to a real
// daemon, and the meta tier substitutes a stub to drive every failure path
// without waiting on Docker to fail for it.
type Runtime interface {
	// Start launches request and waits for its readiness strategy.
	Start(ctx context.Context, request testcontainers.ContainerRequest) (Container, error)
}

// DockerRuntime is the default [Runtime]: testcontainers-go against the ambient
// Docker daemon.
type DockerRuntime struct{}

// Start launches the request through testcontainers-go with Started set, so the
// call returns only once the request's wait strategy is satisfied.
func (DockerRuntime) Start(ctx context.Context, request testcontainers.ContainerRequest) (Container, error) {
	started, err := testcontainers.GenericContainer(ctx, testcontainers.GenericContainerRequest{
		ContainerRequest: request,
		Started:          true,
	})
	if err != nil {
		return nil, err
	}
	return dockerContainer{inner: started}, nil
}

// dockerContainer adapts a testcontainers container onto [Container], so the
// testcontainers types stay behind the seam instead of leaking into every
// helper signature.
type dockerContainer struct {
	inner testcontainers.Container
}

// Host returns the host the container is reachable at.
func (d dockerContainer) Host(ctx context.Context) (string, error) {
	return d.inner.Host(ctx)
}

// Port returns the published host port for an in-container port spec.
func (d dockerContainer) Port(ctx context.Context, spec string) (int, error) {
	mapped, err := d.inner.MappedPort(ctx, spec)
	if err != nil {
		return 0, err
	}
	return int(mapped.Num()), nil
}

// Terminate stops and removes the container.
func (d dockerContainer) Terminate(ctx context.Context) error {
	return d.inner.Terminate(ctx)
}

// runtimeOr returns the configured runtime, defaulting to [DockerRuntime].
func runtimeOr(runtime Runtime) Runtime {
	if runtime == nil {
		return DockerRuntime{}
	}
	return runtime
}

// valueOr returns fallback when value is blank, so every option struct reads as
// "override this" rather than "remember to set this".
func valueOr(value, fallback string) string {
	if value == "" {
		return fallback
	}
	return value
}

// reachable is a started container plus the address it published.
type reachable struct {
	container Container
	host      string
	port      int
}

// endpoint starts request and resolves the host and published port for spec,
// terminating the container if the address cannot be resolved.
//
// A container that started but whose address is unreachable would otherwise
// leak: the caller gets an error and no handle to stop it with.
func endpoint(
	ctx context.Context,
	runtime Runtime,
	request testcontainers.ContainerRequest,
	spec string,
) (reachable, error) {
	container, err := runtimeOr(runtime).Start(ctx, request)
	if err != nil {
		return reachable{}, err
	}
	host, err := container.Host(ctx)
	if err != nil {
		return reachable{}, discard(ctx, container, err)
	}
	port, err := container.Port(ctx, spec)
	if err != nil {
		return reachable{}, discard(ctx, container, err)
	}
	return reachable{container: container, host: host, port: port}, nil
}

// discard terminates a container whose startup could not be completed and
// returns the original cause, so a cleanup failure never hides the real one.
func discard(ctx context.Context, container Container, cause error) error {
	_ = container.Terminate(ctx)
	return cause
}
