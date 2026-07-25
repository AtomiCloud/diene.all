package testhelper_test

import (
	"errors"
	"fmt"
	"net/http"
	"strings"
	"testing"

	"github.com/AtomiCloud/diene.go-api-engine/lib/apiengine"
	"github.com/AtomiCloud/diene.go-api-engine/testhelper"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

// recorder is the double the assertion helpers are proven against: an
// assertion nobody has watched fail is an assertion nobody has tested.
type recorder struct {
	helpers  int
	failures []string
}

func (r *recorder) Helper() { r.helpers++ }

func (r *recorder) Errorf(format string, args ...any) {
	r.failures = append(r.failures, fmt.Sprintf(format, args...))
}

func (r *recorder) failed() bool { return len(r.failures) > 0 }

// sampleError returns a problem-typed error carrying a full envelope.
func sampleError() error {
	return problem.NewError(testhelper.ProblemResponse(testhelper.ProblemOptions{
		Type:        "https://docs.example.com/docs/prod/api/billing/core/v1/quota-exceeded",
		Title:       "Quota exceeded",
		Status:      http.StatusTooManyRequests,
		Detail:      "the monthly quota is spent",
		Instance:    "urn:call:9f2",
		Recoverable: true,
		Data:        map[string]any{"limit": float64(100)},
	}))
}

func fullExpectation() testhelper.ProblemOptions {
	return testhelper.ProblemOptions{
		Type:     "https://docs.example.com/docs/prod/api/billing/core/v1/quota-exceeded",
		Title:    "Quota exceeded",
		Status:   http.StatusTooManyRequests,
		Detail:   "the monthly quota is spent",
		Instance: "urn:call:9f2",
		Data:     map[string]any{"limit": float64(100)},
	}
}

func TestAssertProblemPassesOnKnownGood(t *testing.T) {
	t.Parallel()

	spy := &recorder{}
	envelope := testhelper.AssertProblem(spy, sampleError(), fullExpectation())
	if spy.failed() {
		t.Errorf("AssertProblem on a matching envelope failed: %v", spy.failures)
	}
	if spy.helpers == 0 {
		t.Error("AssertProblem must mark itself a helper so failures point at the caller")
	}
	if envelope.Title != "Quota exceeded" {
		t.Errorf("returned envelope = %+v, want the decoded problem", envelope)
	}
}

// Every member the assertion compares must be proven to fail on a known-bad
// value, or the assertion is decorative.
func TestAssertProblemFailsOnEachMismatchedMember(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name   string
		mutate func(*testhelper.ProblemOptions)
		want   string
	}{
		{"type", func(o *testhelper.ProblemOptions) { o.Type = "https://other" }, "problem type"},
		{"title", func(o *testhelper.ProblemOptions) { o.Title = "Other" }, "problem title"},
		{"status", func(o *testhelper.ProblemOptions) { o.Status = http.StatusTeapot }, "problem status"},
		{"detail", func(o *testhelper.ProblemOptions) { o.Detail = "something else" }, "problem detail"},
		{"instance", func(o *testhelper.ProblemOptions) { o.Instance = "urn:other" }, "problem instance"},
		{"data", func(o *testhelper.ProblemOptions) {
			o.Data = map[string]any{"limit": float64(999)}
		}, "problem data"},
	}
	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			t.Parallel()
			want := fullExpectation()
			testCase.mutate(&want)

			spy := &recorder{}
			testhelper.AssertProblem(spy, sampleError(), want)
			if !spy.failed() {
				t.Fatalf("AssertProblem accepted a mismatched %s", testCase.name)
			}
			if !strings.Contains(spy.failures[0], testCase.want) {
				t.Errorf("failure %q does not name the %s mismatch", spy.failures[0], testCase.name)
			}
		})
	}
}

func TestAssertProblemFailsOnAPlainError(t *testing.T) {
	t.Parallel()

	spy := &recorder{}
	testhelper.AssertProblem(spy, errors.New("just an error"), testhelper.ProblemOptions{})
	if !spy.failed() {
		t.Fatal("AssertProblem accepted an error carrying no envelope")
	}
	if !strings.Contains(spy.failures[0], "problem-typed") {
		t.Errorf("failure %q does not explain what was missing", spy.failures[0])
	}
}

// An absent optional member must fail an expectation that names it, rather
// than silently passing on nil.
func TestCheckProblemFailsWhenAnOptionalMemberIsAbsent(t *testing.T) {
	t.Parallel()

	bare := problem.NewError(testhelper.ProblemResponse(testhelper.ProblemOptions{
		Type: "https://x", Title: "T", Status: 400,
	}))

	if _, err := testhelper.CheckProblem(bare, testhelper.ProblemOptions{Detail: "expected"}); err == nil {
		t.Error("CheckProblem accepted an absent detail")
	} else if !strings.Contains(err.Error(), "<absent>") {
		t.Errorf("failure %q should say the member was absent", err)
	}

	if _, err := testhelper.CheckProblem(bare, testhelper.ProblemOptions{Instance: "urn:x"}); err == nil {
		t.Error("CheckProblem accepted an absent instance")
	} else if !strings.Contains(err.Error(), "<absent>") {
		t.Errorf("failure %q should say the member was absent", err)
	}
}

// An unset expectation member is not compared, so a test asserts only what it
// cares about.
func TestCheckProblemIgnoresUnsetExpectations(t *testing.T) {
	t.Parallel()

	if _, err := testhelper.CheckProblem(sampleError(), testhelper.ProblemOptions{}); err != nil {
		t.Errorf("an empty expectation should match anything problem-typed: %v", err)
	}
	if _, err := testhelper.CheckProblem(sampleError(), testhelper.ProblemOptions{
		Status: http.StatusTooManyRequests,
	}); err != nil {
		t.Errorf("a single-member expectation should match: %v", err)
	}
}

func TestAssertOutcome(t *testing.T) {
	t.Parallel()

	good := &recorder{}
	testhelper.AssertOutcome(good, apiengine.OutcomeProblem, apiengine.OutcomeProblem)
	if good.failed() {
		t.Errorf("AssertOutcome rejected a matching outcome: %v", good.failures)
	}

	bad := &recorder{}
	testhelper.AssertOutcome(bad, apiengine.OutcomeSuccess, apiengine.OutcomeTransport)
	if !bad.failed() {
		t.Fatal("AssertOutcome accepted a mismatched outcome")
	}
	if !strings.Contains(bad.failures[0], "transport") {
		t.Errorf("failure %q does not name the expected outcome", bad.failures[0])
	}
	if err := testhelper.CheckOutcome(apiengine.OutcomeSuccess, apiengine.OutcomeSuccess); err != nil {
		t.Errorf("CheckOutcome on a match: %v", err)
	}
}

func TestAssertCount(t *testing.T) {
	t.Parallel()

	backend := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{})
	defer backend.Close()

	good := &recorder{}
	testhelper.AssertCount(good, backend, 0)
	if good.failed() {
		t.Errorf("AssertCount rejected a matching count: %v", good.failures)
	}

	bad := &recorder{}
	testhelper.AssertCount(bad, backend, 3)
	if !bad.failed() {
		t.Fatal("AssertCount accepted a mismatched count")
	}
	if !strings.Contains(bad.failures[0], "request count") {
		t.Errorf("failure %q does not name the mismatch", bad.failures[0])
	}
	if err := testhelper.CheckCount(backend, 0); err != nil {
		t.Errorf("CheckCount on a match: %v", err)
	}
}
