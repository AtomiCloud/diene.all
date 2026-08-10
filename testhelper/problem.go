// Package testhelper ships the Problem assertion helpers and builders that
// consumers of github.com/AtomiCloud/diene.go-errors-problems would otherwise
// repeat in every test: recovering a [problem.Problem] from a (T, error) result
// via errors.As, matching it field by field, and minting valid fixtures whose
// type URIs come from the single-source builder.
//
// The assertion helpers depend only on the minimal [TestingT] interface (which
// *testing.T satisfies), never on the concrete testing type, so they stay
// framework-free and are themselves black-box testable with a recording double.
package testhelper

import (
	"errors"
	"fmt"
	"reflect"
	"strings"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

// TestingT is the minimal subset of *testing.T the assertion helpers use. Any
// type with Helper and Fatalf satisfies it, which keeps the helpers decoupled
// from the concrete testing type and unit-testable in the meta tier.
type TestingT interface {
	Helper()
	Fatalf(format string, args ...any)
}

// Option constrains one expected field of a [problem.Problem]. Only the fields
// named by the supplied options are checked, and the first mismatch wins.
type Option func(problem.Problem) error

// ExpectType asserts the envelope's Type equals want.
func ExpectType(want string) Option {
	return func(actual problem.Problem) error {
		if actual.Type != want {
			return fmt.Errorf("type mismatch: expected %q, got %q", want, actual.Type)
		}
		return nil
	}
}

// ExpectID asserts the final path segment of the envelope's Type equals want,
// so callers can match a problem id without spelling out the full type URI.
func ExpectID(want string) Option {
	return func(actual problem.Problem) error {
		got := actual.Type
		if index := strings.LastIndex(got, "/"); index >= 0 {
			got = got[index+1:]
		}
		if got != want {
			return fmt.Errorf("id mismatch: expected %q, got %q (from type %q)", want, got, actual.Type)
		}
		return nil
	}
}

// ExpectTitle asserts the envelope's Title equals want.
func ExpectTitle(want string) Option {
	return func(actual problem.Problem) error {
		if actual.Title != want {
			return fmt.Errorf("title mismatch: expected %q, got %q", want, actual.Title)
		}
		return nil
	}
}

// ExpectStatus asserts the envelope's Status equals want.
func ExpectStatus(want int) Option {
	return func(actual problem.Problem) error {
		if actual.Status != want {
			return fmt.Errorf("status mismatch: expected %d, got %d", want, actual.Status)
		}
		return nil
	}
}

// ExpectRecoverable asserts the envelope's Recoverable flag equals want.
//
//nolint:revive // want is a matched value, not a control flag.
func ExpectRecoverable(want bool) Option {
	return func(actual problem.Problem) error {
		if actual.Recoverable != want {
			return fmt.Errorf("recoverable mismatch: expected %t, got %t", want, actual.Recoverable)
		}
		return nil
	}
}

// ExpectDetail asserts the envelope's Detail is present and equals want. A nil
// (absent) Detail never matches.
func ExpectDetail(want string) Option {
	return func(actual problem.Problem) error {
		if actual.Detail == nil || *actual.Detail != want {
			got := "<nil>"
			if actual.Detail != nil {
				got = fmt.Sprintf("%q", *actual.Detail)
			}
			return fmt.Errorf("detail mismatch: expected %q, got %s", want, got)
		}
		return nil
	}
}

// ExpectInstance asserts the envelope's Instance is present and equals want. A
// nil (absent) Instance never matches.
func ExpectInstance(want string) Option {
	return func(actual problem.Problem) error {
		if actual.Instance == nil || *actual.Instance != want {
			got := "<nil>"
			if actual.Instance != nil {
				got = fmt.Sprintf("%q", *actual.Instance)
			}
			return fmt.Errorf("instance mismatch: expected %q, got %s", want, got)
		}
		return nil
	}
}

// ExpectData asserts the envelope's Data deep-equals want.
func ExpectData(want map[string]any) Option {
	return func(actual problem.Problem) error {
		if !reflect.DeepEqual(actual.Data, want) {
			return fmt.Errorf("data mismatch: expected %v, got %v", want, actual.Data)
		}
		return nil
	}
}

// CheckProblem returns the first field mismatch between actual and the supplied
// expectations, or nil when every checked field matches.
func CheckProblem(actual problem.Problem, opts ...Option) error {
	for _, opt := range opts {
		if err := opt(actual); err != nil {
			return err
		}
	}
	return nil
}

// AssertProblem fails t (via Fatalf) when actual does not match the supplied
// expectations.
func AssertProblem(t TestingT, actual problem.Problem, opts ...Option) {
	t.Helper()
	if err := CheckProblem(actual, opts...); err != nil {
		t.Fatalf("problem assertion failed: %v", err)
	}
}

// CheckError recovers a [problem.Problem] from a (T, error) result: it
// requires err to be non-nil and to carry a [problem.Error] in its chain
// (via errors.As), then applies the field expectations. It returns the
// recovered envelope, or a descriptive error on any failure.
func CheckError(err error, opts ...Option) (problem.Problem, error) {
	if err == nil {
		return problem.Problem{}, errors.New("expected a problem-typed error, got nil")
	}
	var problemErr *problem.Error
	if !errors.As(err, &problemErr) {
		return problem.Problem{}, fmt.Errorf("expected a *problem.Error, got %T", err)
	}
	// errors.As also matches a typed-nil *problem.Error; guard it so the helper
	// returns a descriptive mismatch instead of dereferencing nil.
	if problemErr == nil {
		return problem.Problem{}, fmt.Errorf("expected a non-nil *problem.Error, got a typed-nil %T", err)
	}
	if checkErr := CheckProblem(problemErr.Problem, opts...); checkErr != nil {
		return problem.Problem{}, checkErr
	}
	return problemErr.Problem, nil
}

// AssertError fails t (via Fatalf) unless err carries a
// [problem.Error] matching the expectations, and returns the recovered
// envelope on success.
func AssertError(t TestingT, err error, opts ...Option) problem.Problem {
	t.Helper()
	envelope, checkErr := CheckError(err, opts...)
	if checkErr != nil {
		t.Fatalf("problem-error assertion failed: %v", checkErr)
	}
	return envelope
}

// SampleErrorPortal returns a realistic, valid [problem.ErrorPortal] for tests,
// so fixtures never hand-format the type-URI template.
func SampleErrorPortal() problem.ErrorPortal {
	return problem.ErrorPortal{
		Scheme:    "https",
		Host:      "docs.raichu.cluster.atomi.cloud",
		Landscape: "raichu",
		Platform:  "go",
		Service:   "user",
		Module:    "api",
	}
}

// SampleProblem returns a valid entity-not-found [problem.Problem] whose type
// URI is minted by the single-source builder from [SampleErrorPortal].
func SampleProblem() problem.Problem {
	typeURI, _ := problem.TypeURI(SampleErrorPortal(), "v1", "entity-not-found")
	return problem.Problem{
		Type:        typeURI,
		Title:       "Entity not found",
		Status:      404,
		Recoverable: false,
		Data:        map[string]any{"resource": "user", "id": 42},
	}
}
