package health_test

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-consumer/lib/health"
	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
	interfacestest "github.com/AtomiCloud/diene.go-interfaces/testhelper"
)

type codecFake struct {
	marshalPayload  []byte
	marshalErr      error
	unmarshalRecord health.Record
	unmarshalErr    error
}

func (c codecFake) Marshal(any) ([]byte, error) {
	return append([]byte(nil), c.marshalPayload...), c.marshalErr
}

func (c codecFake) Unmarshal(_ []byte, target any) error {
	if c.unmarshalErr != nil {
		return c.unmarshalErr
	}
	record, ok := target.(*health.Record)
	if !ok {
		return errors.New("unexpected codec target")
	}
	*record = c.unmarshalRecord
	return nil
}

func newHeartbeat(
	t *testing.T,
	filesystem interfaces.Vfs,
	system interfaces.System,
	options health.Options,
) *health.FileHeartbeat {
	t.Helper()
	subject, err := health.NewFileHeartbeat(filesystem, system, options)
	if err != nil {
		t.Fatalf("NewFileHeartbeat() error = %v", err)
	}
	return subject
}

func TestNewFileHeartbeatValidatesOptions(t *testing.T) {
	t.Parallel()

	filesystem := interfacestest.NewInMemoryVfs(interfacestest.InMemoryVfsOptions{})
	system := interfacestest.NewInMemorySystem(interfacestest.InMemorySystemOptions{})
	valid := health.Options{Path: "/run/heartbeat.json", MaxAge: time.Second, PID: 7}
	tests := map[string]struct {
		filesystem interfaces.Vfs
		system     interfaces.System
		options    health.Options
		want       string
	}{
		"filesystem": {nil, system, valid, "filesystem is required"},
		"system":     {filesystem, nil, valid, "system is required"},
		"path":       {filesystem, system, health.Options{Path: " ", MaxAge: time.Second, PID: 7}, "heartbeat path is required"},
		"max age":    {filesystem, system, health.Options{Path: valid.Path, PID: 7}, "max age must be positive"},
		"pid":        {filesystem, system, health.Options{Path: valid.Path, MaxAge: time.Second}, "pid must be positive"},
	}
	for name, test := range tests {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			if _, err := health.NewFileHeartbeat(test.filesystem, test.system, test.options); err == nil || !strings.Contains(err.Error(), test.want) {
				t.Fatalf("NewFileHeartbeat() error = %v, want containing %q", err, test.want)
			}
		})
	}
}

func TestStateValidity(t *testing.T) {
	t.Parallel()

	for _, state := range []health.State{health.StateStarting, health.StateHealthy, health.StateStopping} {
		if !state.Valid() {
			t.Fatalf("State.Valid() = false for %q", state)
		}
	}
	if health.State("unknown").Valid() {
		t.Fatal("State.Valid() = true for an unknown state")
	}
}

func TestJSONCodecRoundTrip(t *testing.T) {
	t.Parallel()

	want := health.Record{PID: 42, State: health.StateHealthy, Timestamp: time.Date(2026, time.July, 26, 22, 0, 0, 123, time.FixedZone("offset", 3600))}
	payload, err := (health.JSONCodec{}).Marshal(want)
	if err != nil {
		t.Fatalf("Marshal() error = %v", err)
	}
	var got health.Record
	if err := (health.JSONCodec{}).Unmarshal(payload, &got); err != nil {
		t.Fatalf("Unmarshal() error = %v", err)
	}
	if got.PID != want.PID || got.State != want.State || !got.Timestamp.Equal(want.Timestamp) {
		t.Fatalf("round trip = %#v, want %#v", got, want)
	}
}

func TestFileHeartbeatWritesEveryLifecycleState(t *testing.T) {
	t.Parallel()

	for _, state := range []health.State{health.StateStarting, health.StateHealthy, health.StateStopping} {
		t.Run(string(state), func(t *testing.T) {
			t.Parallel()
			now := time.Date(2026, time.July, 26, 22, 1, 2, 3, time.FixedZone("offset", -3600))
			filesystem := interfacestest.NewInMemoryVfs(interfacestest.InMemoryVfsOptions{})
			system := interfacestest.NewInMemorySystem(interfacestest.InMemorySystemOptions{Now: now})
			subject := newHeartbeat(t, filesystem, system, health.Options{
				Path:   "/run/heartbeat.json",
				MaxAge: time.Minute,
				PID:    73,
			})

			if err := subject.Write(context.Background(), state); err != nil {
				t.Fatalf("Write() error = %v", err)
			}
			payload := filesystem.Files()["/run/heartbeat.json"]
			var record health.Record
			if err := (health.JSONCodec{}).Unmarshal(payload, &record); err != nil {
				t.Fatalf("Unmarshal() error = %v", err)
			}
			if record.PID != 73 || record.State != state || !record.Timestamp.Equal(now) || record.Timestamp.Location() != time.UTC {
				t.Fatalf("written record = %#v", record)
			}
		})
	}
}

func TestFileHeartbeatWriteFailures(t *testing.T) {
	t.Parallel()

	now := time.Date(2026, time.July, 26, 22, 0, 0, 0, time.UTC)
	t.Run("invalid state", func(t *testing.T) {
		t.Parallel()
		subject := newHeartbeat(
			t,
			interfacestest.NewInMemoryVfs(interfacestest.InMemoryVfsOptions{}),
			interfacestest.NewInMemorySystem(interfacestest.InMemorySystemOptions{Now: now}),
			health.Options{Path: "/heartbeat.json", MaxAge: time.Second, PID: 1},
		)
		if err := subject.Write(context.Background(), health.State("bad")); err == nil || !strings.Contains(err.Error(), "invalid heartbeat state") {
			t.Fatalf("Write() error = %v", err)
		}
	})
	t.Run("clock", func(t *testing.T) {
		t.Parallel()
		want := errors.New("clock unavailable")
		system := interfacestest.NewInMemorySystem(interfacestest.InMemorySystemOptions{})
		system.EnqueueClockResult(time.Time{}, want)
		subject := newHeartbeat(t, interfacestest.NewInMemoryVfs(interfacestest.InMemoryVfsOptions{}), system, health.Options{Path: "/heartbeat.json", MaxAge: time.Second, PID: 1})
		if err := subject.Write(context.Background(), health.StateHealthy); !errors.Is(err, want) {
			t.Fatalf("Write() error = %v, want wrapping %v", err, want)
		}
	})
	t.Run("codec", func(t *testing.T) {
		t.Parallel()
		want := errors.New("codec unavailable")
		subject := newHeartbeat(
			t,
			interfacestest.NewInMemoryVfs(interfacestest.InMemoryVfsOptions{}),
			interfacestest.NewInMemorySystem(interfacestest.InMemorySystemOptions{Now: now}),
			health.Options{Path: "/heartbeat.json", MaxAge: time.Second, PID: 1, Codec: codecFake{marshalErr: want}},
		)
		if err := subject.Write(context.Background(), health.StateHealthy); !errors.Is(err, want) {
			t.Fatalf("Write() error = %v, want wrapping %v", err, want)
		}
	})
	t.Run("filesystem", func(t *testing.T) {
		t.Parallel()
		want := errors.New("write unavailable")
		filesystem := interfacestest.NewInMemoryVfs(interfacestest.InMemoryVfsOptions{})
		filesystem.EnqueueWriteBytesResult(want)
		subject := newHeartbeat(t, filesystem, interfacestest.NewInMemorySystem(interfacestest.InMemorySystemOptions{Now: now}), health.Options{
			Path:   "/heartbeat.json",
			MaxAge: time.Second,
			PID:    1,
			Codec:  codecFake{marshalPayload: []byte("record")},
		})
		if err := subject.Write(context.Background(), health.StateHealthy); !errors.Is(err, want) {
			t.Fatalf("Write() error = %v, want wrapping %v", err, want)
		}
	})
}

func TestFileHeartbeatCheckVerdicts(t *testing.T) {
	t.Parallel()

	now := time.Date(2026, time.July, 26, 22, 0, 0, 0, time.UTC)
	tests := map[string]struct {
		record     health.Record
		wantAge    int64
		wantHealth bool
		wantReason string
	}{
		"healthy":  {health.Record{PID: 1, State: health.StateHealthy, Timestamp: now.Add(-time.Second)}, 1000, true, health.ReasonHealthy},
		"boundary": {health.Record{PID: 1, State: health.StateHealthy, Timestamp: now.Add(-time.Minute)}, 60000, true, health.ReasonHealthy},
		"stale":    {health.Record{PID: 1, State: health.StateHealthy, Timestamp: now.Add(-time.Minute - time.Nanosecond)}, 60000, false, health.ReasonUnhealthy},
		"future":   {health.Record{PID: 1, State: health.StateHealthy, Timestamp: now.Add(time.Millisecond)}, -1, false, health.ReasonUnhealthy},
		"starting": {health.Record{PID: 1, State: health.StateStarting, Timestamp: now}, 0, false, health.ReasonUnhealthy},
		"stopping": {health.Record{PID: 1, State: health.StateStopping, Timestamp: now}, 0, false, health.ReasonUnhealthy},
	}
	for name, test := range tests {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			filesystem := interfacestest.NewInMemoryVfs(interfacestest.InMemoryVfsOptions{Files: map[string][]byte{"/heartbeat.json": []byte("record")}})
			subject := newHeartbeat(t, filesystem, interfacestest.NewInMemorySystem(interfacestest.InMemorySystemOptions{Now: now}), health.Options{
				Path:   "/heartbeat.json",
				MaxAge: time.Minute,
				PID:    1,
				Codec:  codecFake{unmarshalRecord: test.record},
			})
			actual := subject.Check(context.Background())
			if actual.AgeMS == nil || *actual.AgeMS != test.wantAge || actual.Healthy != test.wantHealth || actual.Reason != test.wantReason {
				t.Fatalf("Check() = %#v, want age %d, healthy %t, reason %q", actual, test.wantAge, test.wantHealth, test.wantReason)
			}
		})
	}
}

func TestFileHeartbeatCheckFailuresAreUnhealthy(t *testing.T) {
	t.Parallel()

	now := time.Date(2026, time.July, 26, 22, 0, 0, 0, time.UTC)
	tests := map[string]struct {
		filesystem *interfacestest.InMemoryVfs
		system     *interfacestest.InMemorySystem
		codec      health.Codec
		want       string
	}{
		"read": {
			filesystem: interfacestest.NewInMemoryVfs(interfacestest.InMemoryVfsOptions{}),
			system:     interfacestest.NewInMemorySystem(interfacestest.InMemorySystemOptions{Now: now}),
			codec:      codecFake{},
			want:       "heartbeat unreadable",
		},
		"decode": {
			filesystem: interfacestest.NewInMemoryVfs(interfacestest.InMemoryVfsOptions{Files: map[string][]byte{"/heartbeat.json": []byte("bad")}}),
			system:     interfacestest.NewInMemorySystem(interfacestest.InMemorySystemOptions{Now: now}),
			codec:      codecFake{unmarshalErr: errors.New("decode unavailable")},
			want:       "heartbeat invalid: decode unavailable",
		},
		"invalid pid": {
			filesystem: interfacestest.NewInMemoryVfs(interfacestest.InMemoryVfsOptions{Files: map[string][]byte{"/heartbeat.json": []byte("record")}}),
			system:     interfacestest.NewInMemorySystem(interfacestest.InMemorySystemOptions{Now: now}),
			codec:      codecFake{unmarshalRecord: health.Record{State: health.StateHealthy, Timestamp: now}},
			want:       "heartbeat invalid",
		},
		"invalid state": {
			filesystem: interfacestest.NewInMemoryVfs(interfacestest.InMemoryVfsOptions{Files: map[string][]byte{"/heartbeat.json": []byte("record")}}),
			system:     interfacestest.NewInMemorySystem(interfacestest.InMemorySystemOptions{Now: now}),
			codec:      codecFake{unmarshalRecord: health.Record{PID: 1, State: health.State("bad"), Timestamp: now}},
			want:       "heartbeat invalid",
		},
		"zero timestamp": {
			filesystem: interfacestest.NewInMemoryVfs(interfacestest.InMemoryVfsOptions{Files: map[string][]byte{"/heartbeat.json": []byte("record")}}),
			system:     interfacestest.NewInMemorySystem(interfacestest.InMemorySystemOptions{Now: now}),
			codec:      codecFake{unmarshalRecord: health.Record{PID: 1, State: health.StateHealthy}},
			want:       "heartbeat invalid",
		},
	}
	clockFilesystem := interfacestest.NewInMemoryVfs(interfacestest.InMemoryVfsOptions{Files: map[string][]byte{"/heartbeat.json": []byte("record")}})
	clockSystem := interfacestest.NewInMemorySystem(interfacestest.InMemorySystemOptions{})
	clockSystem.EnqueueClockResult(time.Time{}, errors.New("clock unavailable"))
	tests["clock"] = struct {
		filesystem *interfacestest.InMemoryVfs
		system     *interfacestest.InMemorySystem
		codec      health.Codec
		want       string
	}{
		filesystem: clockFilesystem,
		system:     clockSystem,
		codec:      codecFake{unmarshalRecord: health.Record{PID: 1, State: health.StateHealthy, Timestamp: now}},
		want:       "heartbeat clock unavailable",
	}

	for name, test := range tests {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			subject := newHeartbeat(t, test.filesystem, test.system, health.Options{Path: "/heartbeat.json", MaxAge: time.Minute, PID: 1, Codec: test.codec})
			actual := subject.Check(context.Background())
			if actual.Healthy || actual.AgeMS != nil || !strings.Contains(actual.Reason, test.want) {
				t.Fatalf("Check() = %#v, want unhealthy reason containing %q", actual, test.want)
			}
		})
	}
}
