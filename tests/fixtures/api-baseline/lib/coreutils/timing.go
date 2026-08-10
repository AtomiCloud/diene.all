package coreutils

import (
	"context"
	"errors"
	"time"
)

// Sleep waits for duration or returns when ctx is cancelled. Negative durations
// are rejected before a timer is scheduled.
func Sleep(ctx context.Context, duration time.Duration) error {
	if duration < 0 {
		return errors.New("duration must not be negative")
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
