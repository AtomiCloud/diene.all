package testhelper

import (
	"context"
	"errors"
	"time"

	"github.com/AtomiCloud/diene.go-auth-engine/lib/onboard"
)

// ErrLandscapeUnreachable is the error a fake pinger reports for a landscape a test
// marked unreachable without supplying an error of its own.
var ErrLandscapeUnreachable = errors.New("fake pinger cannot reach landscape")

// Ping implements [onboard.Pinger]. A landscape with no configured latency and no
// configured error is treated as unreachable, so a test never accidentally picks a
// region it forgot to script.
func (p *FakePinger) Ping(_ context.Context, landscape onboard.Landscape) (time.Duration, error) {
	p.mutex.Lock()
	defer p.mutex.Unlock()
	p.calls = append(p.calls, landscape.Name)
	if err, failed := p.errors[landscape.Name]; failed {
		return 0, err
	}
	milliseconds, known := p.latencies[landscape.Name]
	if !known {
		return 0, ErrLandscapeUnreachable
	}
	return time.Duration(milliseconds) * time.Millisecond, nil
}
