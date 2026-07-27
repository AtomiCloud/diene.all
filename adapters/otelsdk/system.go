package otelsdk

import (
	"context"
	"os"
	"time"

	"github.com/AtomiCloud/diene.go-otel/lib/otel"
)

// System is the process-backed [interfaces.System] this engine reads OTEL_*
// variables through. The shared interfaces library ships the seam and its
// in-memory mock but no host implementation, so the engine supplies the small
// one it needs and consumers keep injecting their own where they have one.
type System struct{}

// NewSystem returns the process-backed environment seam.
func NewSystem() *System { return &System{} }

// Environment looks up one process environment variable. A nil result means the
// variable is absent; a pointer to an empty string means it is present and empty.
func (*System) Environment(name string) (*string, error) {
	value, present := os.LookupEnv(name)
	if !present {
		return nil, nil
	}
	return &value, nil
}

// CurrentDirectory returns the current working directory as an absolute path.
func (*System) CurrentDirectory() (string, error) {
	directory, err := os.Getwd()
	if err != nil {
		return "", otel.WrapFault(otel.FaultEnvironmentUnavailable, "Environment unavailable",
			"the working directory could not be resolved", otel.FaultStatusUnavailable, err)
	}
	return directory, nil
}

// NowUTC returns the current instant in UTC.
func (*System) NowUTC() (time.Time, error) { return time.Now().UTC(), nil }

// Delay waits for duration or returns when ctx is cancelled.
func (*System) Delay(ctx context.Context, duration time.Duration) error {
	if duration <= 0 {
		return ctx.Err()
	}
	timer := time.NewTimer(duration)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-timer.C:
		return nil
	}
}
