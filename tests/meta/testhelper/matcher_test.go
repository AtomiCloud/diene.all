package testhelper_test

import (
	"errors"
	"fmt"
	"strings"
	"testing"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
	"github.com/AtomiCloud/diene.go-errors-problems/testhelper"
)

// recordingT is a TestingT double: it records the first Fatalf so the meta tier
// can assert the asserter fails on known-bad input without aborting the test.
type recordingT struct {
	failed  bool
	message string
}

func (*recordingT) Helper() {}

func (r *recordingT) Fatalf(format string, args ...any) {
	r.failed = true
	r.message = fmt.Sprintf(format, args...)
}

func goodProblem() problem.Problem {
	detail, instance := "missing", "/x"
	return problem.Problem{
		Type:        "https://h/docs/l/p/s/m/v1/entity-not-found",
		Title:       "Entity not found",
		Status:      404,
		Detail:      &detail,
		Instance:    &instance,
		Recoverable: false,
		Data:        map[string]any{"resource": "user", "id": 42},
	}
}

func TestCheckProblemPassesOnEveryField(t *testing.T) {
	t.Parallel()
	good := goodProblem()
	err := testhelper.CheckProblem(
		good,
		testhelper.ExpectType(good.Type),
		testhelper.ExpectID("entity-not-found"),
		testhelper.ExpectTitle(good.Title),
		testhelper.ExpectStatus(good.Status),
		testhelper.ExpectRecoverable(good.Recoverable),
		testhelper.ExpectDetail(*good.Detail),
		testhelper.ExpectInstance(*good.Instance),
		testhelper.ExpectData(good.Data),
	)
	if err != nil {
		t.Fatalf("expected pass, got %v", err)
	}
}

func TestCheckProblemPassesWithSubsetOfFields(t *testing.T) {
	t.Parallel()
	if err := testhelper.CheckProblem(goodProblem(), testhelper.ExpectStatus(404)); err != nil {
		t.Fatalf("subset check should pass, got %v", err)
	}
}

func TestCheckProblemFailsPerField(t *testing.T) {
	t.Parallel()
	good := goodProblem()
	cases := map[string]testhelper.Option{
		"type":        testhelper.ExpectType("https://other"),
		"id":          testhelper.ExpectID("conflict"),
		"title":       testhelper.ExpectTitle("Wrong"),
		"status":      testhelper.ExpectStatus(500),
		"recoverable": testhelper.ExpectRecoverable(true),
		"detail":      testhelper.ExpectDetail("other"),
		"instance":    testhelper.ExpectInstance("/other"),
		"data":        testhelper.ExpectData(map[string]any{"resource": "user", "id": 99}),
	}
	for name, option := range cases {
		if err := testhelper.CheckProblem(good, option); err == nil {
			t.Fatalf("%s mismatch should fail", name)
		} else if !strings.Contains(err.Error(), "mismatch") {
			t.Fatalf("%s: unexpected message %q", name, err.Error())
		}
	}
}

func TestAssertProblemReportsPassAndFailure(t *testing.T) {
	t.Parallel()
	pass := &recordingT{}
	testhelper.AssertProblem(pass, goodProblem(), testhelper.ExpectStatus(404))
	if pass.failed {
		t.Fatalf("known-good should not fail: %s", pass.message)
	}
	fail := &recordingT{}
	testhelper.AssertProblem(fail, goodProblem(), testhelper.ExpectStatus(500))
	if !fail.failed {
		t.Fatal("known-bad should fail")
	}
}

func TestCheckErrorRecoversEnvelope(t *testing.T) {
	t.Parallel()
	good := goodProblem()
	err := fmt.Errorf("context: %w", problem.NewError(good))
	recovered, checkErr := testhelper.CheckError(err, testhelper.ExpectStatus(404))
	if checkErr != nil {
		t.Fatalf("expected recovery, got %v", checkErr)
	}
	if !recovered.Equal(good) {
		t.Fatalf("recovered mismatch: %+v", recovered)
	}
}

func TestExpectDetailAndInstanceRejectAbsentPointers(t *testing.T) {
	t.Parallel()
	// A nil (absent) Detail/Instance never matches a wanted value, and the
	// matcher reports a descriptive mismatch rather than dereferencing nil.
	absent := problem.Problem{Type: "t", Title: "T", Status: 500}
	detailErr := testhelper.CheckProblem(absent, testhelper.ExpectDetail("missing"))
	if detailErr == nil || !strings.Contains(detailErr.Error(), "detail mismatch") {
		t.Fatalf("absent detail should fail with a mismatch, got %v", detailErr)
	}
	instanceErr := testhelper.CheckProblem(absent, testhelper.ExpectInstance("/x"))
	if instanceErr == nil || !strings.Contains(instanceErr.Error(), "instance mismatch") {
		t.Fatalf("absent instance should fail with a mismatch, got %v", instanceErr)
	}
}

func TestCheckErrorRejectsNil(t *testing.T) {
	t.Parallel()
	if _, err := testhelper.CheckError(nil); err == nil {
		t.Fatal("nil error should be rejected")
	}
}

// TestCheckErrorRejectsTypedNilProblemError is the Blocker-2 regression for the
// consumer TestHelper: a typed-nil *problem.Error matches errors.As but must be
// reported as a descriptive mismatch instead of panicking on a nil deref.
func TestCheckErrorRejectsTypedNilProblemError(t *testing.T) {
	t.Parallel()
	var nilErr *problem.Error
	recovered, err := testhelper.CheckError(nilErr)
	if err == nil {
		t.Fatal("typed-nil *problem.Error should be rejected")
	}
	if !strings.Contains(err.Error(), "typed-nil") {
		t.Fatalf("expected a descriptive typed-nil mismatch, got %q", err.Error())
	}
	if !recovered.Equal(problem.Problem{}) {
		t.Fatalf("expected a zero envelope on rejection, got %+v", recovered)
	}
}

func TestCheckErrorRejectsNonError(t *testing.T) {
	t.Parallel()
	if _, err := testhelper.CheckError(errors.New("plain")); err == nil {
		t.Fatal("non-Error should be rejected")
	}
}

func TestCheckErrorPropagatesFieldMismatch(t *testing.T) {
	t.Parallel()
	err := problem.NewError(goodProblem())
	if _, checkErr := testhelper.CheckError(err, testhelper.ExpectStatus(500)); checkErr == nil {
		t.Fatal("field mismatch should propagate")
	}
}

func TestAssertErrorReportsPassAndFailure(t *testing.T) {
	t.Parallel()
	pass := &recordingT{}
	recovered := testhelper.AssertError(pass, problem.NewError(goodProblem()), testhelper.ExpectID("entity-not-found"))
	if pass.failed {
		t.Fatalf("known-good should not fail: %s", pass.message)
	}
	if recovered.Status != 404 {
		t.Fatalf("expected recovered envelope, got %+v", recovered)
	}
	fail := &recordingT{}
	testhelper.AssertError(fail, errors.New("plain"))
	if !fail.failed {
		t.Fatal("non-Error should fail")
	}
}
