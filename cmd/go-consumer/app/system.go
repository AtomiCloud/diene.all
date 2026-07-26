package app

import (
	"context"
	"maps"
	"path/filepath"
	"time"

	"github.com/AtomiCloud/diene.go-otel/adapters/otelsdk"
)

type invocationSystem struct {
	host             *otelsdk.System
	environment      map[string]string
	workingDirectory string
}

func newInvocationSystem(invocation Invocation) *invocationSystem {
	return &invocationSystem{
		host:             otelsdk.NewSystem(),
		environment:      maps.Clone(invocation.Env),
		workingDirectory: invocation.WorkingDirectory,
	}
}

func (system *invocationSystem) Environment(name string) (*string, error) {
	value, found := system.environment[name]
	if !found {
		return nil, nil
	}
	return &value, nil
}

func (system *invocationSystem) CurrentDirectory() (string, error) {
	if system.workingDirectory == "" {
		return system.host.CurrentDirectory()
	}
	return filepath.Abs(system.workingDirectory)
}

func (system *invocationSystem) NowUTC() (time.Time, error) {
	return system.host.NowUTC()
}

func (system *invocationSystem) Delay(ctx context.Context, duration time.Duration) error {
	return system.host.Delay(ctx, duration)
}
