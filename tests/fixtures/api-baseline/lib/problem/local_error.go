package problem

import "context"

const (
	localErrorID      = "local-error"
	localErrorTitle   = "Local Error"
	localErrorVersion = "v1"
)

// ErrorSink receives unexpected problems captured by [LocalError]. In
// production this forwards to the telemetry path; tests inject a recording sink.
type ErrorSink interface {
	// Capture reports problem, returning any delivery error.
	Capture(ctx context.Context, problem Problem) error
}

// NoopErrorSink is an [ErrorSink] that discards every capture.
type NoopErrorSink struct{}

// Capture discards problem and always succeeds.
func (NoopErrorSink) Capture(_ context.Context, _ Problem) error {
	return nil
}

// LocalError wraps unexpected errors into a `local-error` [Problem] carrying the
// message and stack in `data`, and captures it on a [ErrorSink]. The type URI
// flows through the single-source builder so even local errors share one
// identity shape.
type LocalError struct {
	// Sink is the destination for captured local-error problems.
	Sink ErrorSink
	// Portal builds the local-error type URI.
	Portal ErrorPortal
}

// NewLocalError creates a wrapper writing captures to sink, using
// [LocalErrorPortal] for its type URIs.
func NewLocalError(sink ErrorSink) LocalError {
	return LocalError{Sink: sink, Portal: LocalErrorPortal()}
}

// NewLocalErrorWithPortal creates a wrapper writing captures to sink and
// building type URIs from portal.
func NewLocalErrorWithPortal(sink ErrorSink, portal ErrorPortal) LocalError {
	return LocalError{Sink: sink, Portal: portal}
}

// Wrap folds cause and stack into a `local-error` [Problem], captures it on the
// sink, and returns the envelope. A capture failure is returned alongside the
// (still valid) envelope so callers never lose the problem.
func (local LocalError) Wrap(ctx context.Context, cause error, stack string) (Problem, error) {
	message := ""
	if cause != nil {
		message = cause.Error()
	}
	typeURI, err := TypeURI(local.Portal, localErrorVersion, localErrorID)
	if err != nil {
		typeURI = blankType
	}
	envelope := Problem{
		Type:        typeURI,
		Title:       localErrorTitle,
		Status:      defaultProblemStatus,
		Detail:      message,
		Recoverable: false,
		Data: map[string]any{
			"message": message,
			"stack":   stack,
		},
	}
	if captureErr := local.Sink.Capture(ctx, envelope); captureErr != nil {
		return envelope, captureErr
	}
	return envelope, nil
}
