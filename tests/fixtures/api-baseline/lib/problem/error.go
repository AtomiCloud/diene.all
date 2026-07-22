package problem

// Error is the Go realization of the family "result slot": a concrete
// error that carries a [Problem] and is compatible with errors.Is/errors.As and
// %w wrapping. Fallible APIs return the idiomatic (T, error) pair; consumers
// recover the envelope with:
//
//	var pe *problem.Error
//	if errors.As(err, &pe) {
//		use(pe.Problem)
//	}
type Error struct {
	// Problem is the RFC 9457 envelope this error carries.
	Problem Problem
	wrapped error
}

// NewError creates a problem-typed error carrying problem.
func NewError(problem Problem) *Error {
	return &Error{Problem: problem}
}

// WrapError creates a problem-typed error carrying problem and wrapping cause,
// so errors.Is/errors.As traverse into the underlying error chain.
func WrapError(problem Problem, cause error) *Error {
	return &Error{Problem: problem, wrapped: cause}
}

// Error implements the error interface, appending the wrapped cause when present.
func (e *Error) Error() string {
	if e.wrapped != nil {
		return e.Problem.String() + ": " + e.wrapped.Error()
	}
	return e.Problem.String()
}

// Unwrap returns the wrapped cause (nil when none), enabling errors.Is and
// errors.As to traverse the chain.
func (e *Error) Unwrap() error {
	return e.wrapped
}
