package interfaces

import (
	"context"
	"time"
)

// System is the process and clock boundary used by portable Go libraries.
type System interface {
	// Environment looks up one process environment variable. A nil result means
	// the variable is absent; a pointer to an empty string means it is present.
	Environment(name string) (*string, error)
	// CurrentDirectory returns the current working directory as an absolute path.
	CurrentDirectory() (string, error)
	// NowUTC returns the current instant in UTC.
	NowUTC() (time.Time, error)
	// Delay waits for d or returns when ctx is cancelled.
	Delay(ctx context.Context, d time.Duration) error
}
