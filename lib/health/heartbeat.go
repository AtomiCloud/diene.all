// Package health implements the dependency-blind worker heartbeat.
package health

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
)

// State is the worker lifecycle state written into a heartbeat.
type State string

const (
	// StateStarting reports that the worker is starting.
	StateStarting State = "starting"
	// StateHealthy reports that the worker completed a successful iteration.
	StateHealthy State = "healthy"
	// StateStopping reports that the worker is stopping normally.
	StateStopping State = "stopping"
)

const (
	// ReasonHealthy is returned for a fresh healthy heartbeat.
	ReasonHealthy = "heartbeat healthy"
	// ReasonUnhealthy is returned for a stale, future, or non-healthy heartbeat.
	ReasonUnhealthy = "heartbeat stale or stopping"
)

// Valid reports whether state is one of the three worker lifecycle states.
func (s State) Valid() bool {
	return s == StateStarting || s == StateHealthy || s == StateStopping
}

// Record is the JSON document persisted by a worker.
type Record struct {
	PID       int       `json:"pid"`
	State     State     `json:"state"`
	Timestamp time.Time `json:"timestamp"`
}

// Result is the dependency-blind health verdict printed by the health command.
type Result struct {
	AgeMS   *int64 `json:"ageMs,omitempty"`
	Healthy bool   `json:"healthy"`
	Reason  string `json:"reason"`
}

// Codec encodes and decodes heartbeat documents.
type Codec interface {
	Marshal(value any) ([]byte, error)
	Unmarshal(data []byte, target any) error
}

// JSONCodec is the production heartbeat codec.
type JSONCodec struct{}

// Marshal implements Codec.
func (JSONCodec) Marshal(value any) ([]byte, error) {
	return json.Marshal(value)
}

// Unmarshal implements Codec.
func (JSONCodec) Unmarshal(data []byte, target any) error {
	return json.Unmarshal(data, target)
}

// Options configures a FileHeartbeat.
type Options struct {
	Path   string
	MaxAge time.Duration
	PID    int
	Codec  Codec
}

// FileHeartbeat writes and checks one heartbeat through the portable VFS seam.
type FileHeartbeat struct {
	filesystem interfaces.Vfs
	system     interfaces.System
	path       string
	maxAge     time.Duration
	pid        int
	codec      Codec
}

// NewFileHeartbeat creates a dependency-blind heartbeat service.
func NewFileHeartbeat(filesystem interfaces.Vfs, system interfaces.System, options Options) (*FileHeartbeat, error) {
	if filesystem == nil {
		return nil, errors.New("health: filesystem is required")
	}
	if system == nil {
		return nil, errors.New("health: system is required")
	}
	if strings.TrimSpace(options.Path) == "" {
		return nil, errors.New("health: heartbeat path is required")
	}
	if options.MaxAge <= 0 {
		return nil, errors.New("health: max age must be positive")
	}
	if options.PID <= 0 {
		return nil, errors.New("health: pid must be positive")
	}
	codec := options.Codec
	if codec == nil {
		codec = JSONCodec{}
	}
	return &FileHeartbeat{
		filesystem: filesystem,
		system:     system,
		path:       options.Path,
		maxAge:     options.MaxAge,
		pid:        options.PID,
		codec:      codec,
	}, nil
}

// Write persists the current worker lifecycle state.
func (h *FileHeartbeat) Write(ctx context.Context, state State) error {
	if !state.Valid() {
		return fmt.Errorf("health: invalid heartbeat state %q", state)
	}
	now, err := h.system.NowUTC()
	if err != nil {
		return fmt.Errorf("health: read clock: %w", err)
	}
	payload, err := h.codec.Marshal(Record{PID: h.pid, State: state, Timestamp: now.UTC()})
	if err != nil {
		return fmt.Errorf("health: encode heartbeat: %w", err)
	}
	if err := h.filesystem.WriteBytes(ctx, h.path, payload, interfaces.WriteOptions{CreateParents: true}); err != nil {
		return fmt.Errorf("health: write heartbeat: %w", err)
	}
	return nil
}

// Check reads the heartbeat and returns an unhealthy value for every malformed
// or unreadable state. It never dials Postgres, Redis, storage, or telemetry.
func (h *FileHeartbeat) Check(ctx context.Context) Result {
	payload, err := h.filesystem.ReadBytes(ctx, h.path)
	if err != nil {
		return Result{Healthy: false, Reason: "heartbeat unreadable: " + err.Error()}
	}
	record := Record{}
	if decodeErr := h.codec.Unmarshal(payload, &record); decodeErr != nil {
		return Result{Healthy: false, Reason: "heartbeat invalid: " + decodeErr.Error()}
	}
	if record.PID <= 0 || !record.State.Valid() || record.Timestamp.IsZero() {
		return Result{Healthy: false, Reason: "heartbeat invalid"}
	}
	now, err := h.system.NowUTC()
	if err != nil {
		return Result{Healthy: false, Reason: "heartbeat clock unavailable: " + err.Error()}
	}
	age := now.UTC().Sub(record.Timestamp.UTC())
	ageMS := age.Milliseconds()
	healthy := record.State == StateHealthy && age >= 0 && age <= h.maxAge
	reason := ReasonUnhealthy
	if healthy {
		reason = ReasonHealthy
	}
	return Result{AgeMS: &ageMS, Healthy: healthy, Reason: reason}
}
