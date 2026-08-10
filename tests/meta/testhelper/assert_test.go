package testhelper_test

import (
	"errors"
	"strings"
	"testing"

	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
	"github.com/AtomiCloud/diene.go-auth-engine/lib/onboard"
	"github.com/AtomiCloud/diene.go-auth-engine/testhelper"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

// recorder is the double the meta tier drives the assertion helpers with.
//
// Assert-the-asserter is the whole point of this tier: an assertion that only ever
// runs against passing input proves nothing, because an assertion that never fails
// looks identical to one that works.
type recorder struct {
	helpers  int
	failures []string
}

func (r *recorder) Helper() {
	r.helpers++
}

func (r *recorder) Fatalf(format string, args ...any) {
	r.failures = append(r.failures, sprintf(format, args...))
}

// failed reports whether the recorder saw a failure.
func (r *recorder) failed() bool {
	return len(r.failures) > 0
}

// message returns the first recorded failure.
func (r *recorder) message() string {
	if len(r.failures) == 0 {
		return ""
	}
	return r.failures[0]
}

// sprintf renders a failure message without importing fmt into the assertions
// under test.
func sprintf(format string, args ...any) string {
	rendered := format
	for _, arg := range args {
		rendered = strings.Replace(rendered, "%s", asText(arg), 1)
		rendered = strings.Replace(rendered, "%v", asText(arg), 1)
	}
	return rendered
}

// asText renders one argument.
func asText(value any) string {
	switch typed := value.(type) {
	case string:
		return typed
	case error:
		return typed.Error()
	default:
		return "value"
	}
}

// problems is the engine's factory over the sample portal.
func problems(t *testing.T) *authengine.Problems {
	t.Helper()

	factory, err := authengine.NewProblems(testhelper.SampleErrorPortal())
	if err != nil {
		t.Fatalf("expected a problem factory, got %v", err)
	}
	return factory
}

func TestAssertAuthProblemPassesOnKnownGood(t *testing.T) {
	t.Parallel()

	raised := problems(t).Raise(authengine.ProblemOwnershipDenied, "denied", nil)
	double := &recorder{}

	envelope := testhelper.AssertAuthProblem(double, raised, authengine.ProblemOwnershipDenied)

	if double.failed() {
		t.Fatalf("expected the matching problem to pass, got %q", double.message())
	}
	if envelope.Status != 403 {
		t.Fatalf("expected the recovered envelope, got %+v", envelope)
	}
	if double.helpers == 0 {
		t.Fatal("expected the assertion to mark itself as a helper")
	}
}

func TestAssertAuthProblemFailsOnEveryKnownBad(t *testing.T) {
	t.Parallel()

	factory := problems(t)
	cases := []struct {
		name string
		err  error
	}{
		{name: "no error at all", err: nil},
		{name: "a plain error", err: errors.New("not a problem")},
		{name: "the wrong problem", err: factory.Raise(authengine.ProblemTokenExpired, "expired", nil)},
	}

	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			t.Parallel()

			double := &recorder{}
			testhelper.AssertAuthProblem(double, testCase.err, authengine.ProblemOwnershipDenied)
			if !double.failed() {
				t.Fatal("expected the assertion to fail on known-bad input")
			}
			if !strings.Contains(double.message(), authengine.ProblemOwnershipDenied) {
				t.Fatalf("expected the message to name the expected problem, got %q", double.message())
			}
		})
	}
}

func TestCheckAuthProblemMirrorsTheAssertion(t *testing.T) {
	t.Parallel()

	factory := problems(t)

	envelope, failure := testhelper.CheckAuthProblem(
		factory.Raise(authengine.ProblemTokenExpired, "expired", nil), authengine.ProblemTokenExpired,
	)
	if failure != nil {
		t.Fatalf("expected the matching problem to check clean, got %v", failure)
	}
	if envelope.Status != 401 {
		t.Fatalf("expected the recovered envelope, got %+v", envelope)
	}

	if _, failure := testhelper.CheckAuthProblem(nil, authengine.ProblemTokenExpired); failure == nil {
		t.Fatal("expected a nil error to be reported")
	}
	if _, failure := testhelper.CheckAuthProblem(errors.New("plain"), "x"); failure == nil {
		t.Fatal("expected a plain error to be reported")
	}
}

func TestCheckAuthProblemTraversesAWrappedChain(t *testing.T) {
	t.Parallel()

	raised := problems(t).RaiseFrom(authengine.ProblemProviderUnavailable,
		errors.New("dial tcp"), "unreachable", nil)

	// A consumer's own wrapper must not hide the problem underneath it.
	wrapped := errors.Join(errors.New("while onboarding"), raised)

	if _, failure := testhelper.CheckAuthProblem(
		wrapped, authengine.ProblemProviderUnavailable,
	); failure != nil {
		t.Fatalf("expected the wrapped problem to be recovered, got %v", failure)
	}
}

func TestAssertNoAuthProblemPassesAndFails(t *testing.T) {
	t.Parallel()

	clean := &recorder{}
	testhelper.AssertNoAuthProblem(clean, nil)
	if clean.failed() {
		t.Fatalf("expected a nil error to pass, got %q", clean.message())
	}

	typed := &recorder{}
	testhelper.AssertNoAuthProblem(typed, problems(t).Raise(authengine.ProblemTokenExpired, "expired", nil))
	if !typed.failed() {
		t.Fatal("expected a problem-typed error to fail")
	}
	if !strings.Contains(typed.message(), authengine.ProblemTokenExpired) {
		t.Fatalf("expected the failure to name the problem, got %q", typed.message())
	}

	plain := &recorder{}
	testhelper.AssertNoAuthProblem(plain, errors.New("boom"))
	if !plain.failed() {
		t.Fatal("expected a plain error to fail")
	}
	if !strings.Contains(plain.message(), "boom") {
		t.Fatalf("expected the failure to render the error, got %q", plain.message())
	}
}

func TestAssertOwnershipDeniedIsTheGuardShorthand(t *testing.T) {
	t.Parallel()

	factory := problems(t)

	passing := &recorder{}
	testhelper.AssertOwnershipDenied(passing,
		factory.Raise(authengine.ProblemOwnershipDenied, "denied", nil))
	if passing.failed() {
		t.Fatalf("expected a denial to pass, got %q", passing.message())
	}

	failing := &recorder{}
	testhelper.AssertOwnershipDenied(failing,
		factory.Raise(authengine.ProblemTokenExpired, "expired", nil))
	if !failing.failed() {
		t.Fatal("expected a non-denial to fail")
	}
}

func TestAssertPhasePassesAndFails(t *testing.T) {
	t.Parallel()

	states := map[string]onboard.State{
		"alcohol-zinc": {Backend: "alcohol-zinc", Phase: onboard.PhaseReady},
		"nitroso-tin": {
			Backend: "nitroso-tin",
			Phase:   onboard.PhaseError,
			Err:     errors.New("backend down"),
		},
	}

	passing := &recorder{}
	testhelper.AssertPhase(passing, states, "alcohol-zinc", onboard.PhaseReady)
	if passing.failed() {
		t.Fatalf("expected the matching phase to pass, got %q", passing.message())
	}

	wrong := &recorder{}
	testhelper.AssertPhase(wrong, states, "nitroso-tin", onboard.PhaseReady)
	if !wrong.failed() {
		t.Fatal("expected a mismatched phase to fail")
	}
	// The carried failure is what makes a phase mismatch diagnosable.
	if !strings.Contains(wrong.message(), "backend down") {
		t.Fatalf("expected the failure to be rendered, got %q", wrong.message())
	}

	absent := &recorder{}
	testhelper.AssertPhase(absent, states, "never-ran", onboard.PhaseReady)
	if !absent.failed() {
		t.Fatal("expected an absent backend to fail")
	}
	if !strings.Contains(absent.message(), "never-ran") {
		t.Fatalf("expected the absent backend to be named, got %q", absent.message())
	}
}

func TestCheckPhaseReportsAPhaseWithoutAnError(t *testing.T) {
	t.Parallel()

	states := map[string]onboard.State{
		"alcohol-zinc": {Backend: "alcohol-zinc", Phase: onboard.PhaseNeedsOnboarding},
	}

	failure := testhelper.CheckPhase(states, "alcohol-zinc", onboard.PhaseReady)
	if failure == nil {
		t.Fatal("expected a mismatched phase to be reported")
	}
	if !strings.Contains(failure.Error(), string(onboard.PhaseNeedsOnboarding)) {
		t.Fatalf("expected the actual phase to be named, got %q", failure.Error())
	}
	if testhelper.CheckPhase(states, "alcohol-zinc", onboard.PhaseNeedsOnboarding) != nil {
		t.Fatal("expected the matching phase to check clean")
	}
}

func TestProblemIDReadsTheTrailingSegment(t *testing.T) {
	t.Parallel()

	envelope := problem.Problem{Type: "https://docs.invalid/docs/l/p/s/m/v1/token-expired"}
	if got := testhelper.ProblemID(envelope); got != "token-expired" {
		t.Fatalf("expected the trailing id, got %q", got)
	}
	// RFC 9457's default type has no path at all and must survive unchanged.
	if got := testhelper.ProblemID(problem.Problem{Type: "about:blank"}); got != "about:blank" {
		t.Fatalf("expected a path-less type to be returned whole, got %q", got)
	}
}

func TestSampleErrorPortalMintsValidTypeURIs(t *testing.T) {
	t.Parallel()

	uri, err := problem.TypeURI(testhelper.SampleErrorPortal(), authengine.ProblemVersion,
		authengine.ProblemOwnershipDenied)
	if err != nil {
		t.Fatalf("expected the sample portal to mint a valid URI, got %v", err)
	}
	if !strings.HasSuffix(uri, "/v1/"+authengine.ProblemOwnershipDenied) {
		t.Fatalf("expected a versioned type URI, got %q", uri)
	}
}

func TestFixedNowIsDeterministicAndRealistic(t *testing.T) {
	t.Parallel()

	if !testhelper.FixedNow().Equal(testhelper.FixedNow()) {
		t.Fatal("expected the fixed instant to be stable")
	}
	if testhelper.FixedNow().Year() < 2000 {
		t.Fatalf("expected a plausible date rather than the epoch, got %s", testhelper.FixedNow())
	}
	if testhelper.FixedNow().Location() != timeUTC() {
		t.Fatal("expected the fixed instant to be UTC")
	}
}
