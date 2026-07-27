package problem_test

import (
	"context"
	"errors"
	"testing"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

type recordingSink struct {
	captured []problem.Problem
}

func (s *recordingSink) Capture(_ context.Context, envelope problem.Problem) error {
	s.captured = append(s.captured, envelope)
	return nil
}

type failingSink struct {
	err error
}

func (s failingSink) Capture(_ context.Context, _ problem.Problem) error {
	return s.err
}

func TestNoopErrorSinkCapture(t *testing.T) {
	t.Parallel()
	if err := (problem.NoopErrorSink{}).Capture(context.Background(), problem.Problem{}); err != nil {
		t.Fatalf("noop sink should never error, got %v", err)
	}
}

func TestLocalErrorWrapWithCause(t *testing.T) {
	t.Parallel()
	sink := &recordingSink{}
	local := problem.NewLocalError(sink)
	envelope, err := local.Wrap(context.Background(), errors.New("boom"), "stack-trace")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if envelope.Status != 500 || envelope.Title != "Local Error" {
		t.Fatalf("unexpected envelope: %+v", envelope)
	}
	if envelope.Detail == nil || *envelope.Detail != "boom" ||
		envelope.Data["message"] != "boom" || envelope.Data["stackTrace"] != "stack-trace" {
		t.Fatalf("unexpected payload: %+v", envelope)
	}
	want := "https://local.atomi.cloud/docs/local/go/app/core/v1/local-error"
	if envelope.Type != want {
		t.Fatalf("type = %q, want %q", envelope.Type, want)
	}
	if len(sink.captured) != 1 {
		t.Fatalf("expected 1 capture, got %d", len(sink.captured))
	}
}

func TestLocalErrorWrapWithNilCause(t *testing.T) {
	t.Parallel()
	sink := &recordingSink{}
	local := problem.NewLocalError(sink)
	envelope, err := local.Wrap(context.Background(), nil, "")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	// A nil cause yields an empty message, but detail stays present (a non-nil
	// pointer to "") to mirror the Dart sibling, which always sets detail.
	if envelope.Detail == nil || *envelope.Detail != "" || envelope.Data["message"] != "" {
		t.Fatalf("nil cause should yield present-empty message: %+v", envelope)
	}
}

func TestLocalErrorWrapPropagatesCaptureError(t *testing.T) {
	t.Parallel()
	local := problem.NewLocalError(failingSink{err: errors.New("sink down")})
	envelope, err := local.Wrap(context.Background(), errors.New("boom"), "stack")
	if err == nil || err.Error() != "sink down" {
		t.Fatalf("expected capture error, got %v", err)
	}
	if envelope.Title != "Local Error" {
		t.Fatalf("envelope should still be returned: %+v", envelope)
	}
}

func TestLocalErrorWrapInvalidPortalFallsBackToBlank(t *testing.T) {
	t.Parallel()
	local := problem.NewLocalErrorWithPortal(&recordingSink{}, problem.ErrorPortal{})
	envelope, err := local.Wrap(context.Background(), errors.New("boom"), "stack")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if envelope.Type != "about:blank" {
		t.Fatalf("expected about:blank fallback, got %q", envelope.Type)
	}
}

func TestLocalErrorWrapWithoutSink(t *testing.T) {
	t.Parallel()
	local := problem.NewLocalError(nil)
	envelope, err := local.Wrap(context.Background(), errors.New("boom"), "stack")
	if err != nil {
		t.Fatalf("nil sink should be a no-op, got %v", err)
	}
	if envelope.Title != "Local Error" {
		t.Fatalf("unexpected envelope: %+v", envelope)
	}
}
