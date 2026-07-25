package testhelper_test

import (
	"context"
	"errors"
	"fmt"
	"testing"

	"github.com/AtomiCloud/diene.go-config/lib/config"
	"github.com/AtomiCloud/diene.go-config/testhelper"
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

func invalidLoad(t *testing.T) (*config.Config, error) {
	t.Helper()
	return config.NewLoader(
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(testhelper.BaseSource(testhelper.BaseDocument())),
		config.WithLandscape("lapras"),
		config.WithOverlaySource("lapras", testhelper.OverlaySource("lapras", testhelper.InvalidOverlayDocument())),
		config.WithEnvSource(testhelper.EnvSource(nil)),
		config.WithSchema(testhelper.Schema()),
	).Load(context.Background())
}

func validLoad(t *testing.T) (*config.Config, error) {
	t.Helper()
	return config.NewLoader(
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(testhelper.BaseSource(testhelper.BaseDocument())),
		config.WithEnvSource(testhelper.EnvSource(nil)),
		config.WithSchema(testhelper.Schema()),
	).Load(context.Background())
}

func TestRequireConfigPassesAndFails(t *testing.T) {
	t.Parallel()
	cfg, err := validLoad(t)
	pass := &recordingT{}
	if got := testhelper.RequireConfig(pass, cfg, err); got == nil || pass.failed {
		t.Fatalf("known-good load should pass: failed=%v msg=%s", pass.failed, pass.message)
	}
	fail := &recordingT{}
	testhelper.RequireConfig(fail, nil, errors.New("boom"))
	if !fail.failed {
		t.Fatal("an errored load should fail the asserter")
	}
}

func TestRequireLoadErrorPassesAndFails(t *testing.T) {
	t.Parallel()
	cfg, err := invalidLoad(t)
	pass := &recordingT{}
	if got := testhelper.RequireLoadError(pass, cfg, err); got == nil || pass.failed {
		t.Fatalf("known-bad load should pass the error asserter: failed=%v", pass.failed)
	}
	fail := &recordingT{}
	good, _ := validLoad(t)
	_ = testhelper.RequireLoadError(fail, good, nil)
	if !fail.failed {
		t.Fatal("a successful load should fail the error asserter")
	}
}

func TestRequireIssuePassesAndFails(t *testing.T) {
	t.Parallel()
	_, err := invalidLoad(t)

	pass := &recordingT{}
	issue := testhelper.RequireIssue(pass, err, "app.version")
	if pass.failed || issue.Path != "app.version" {
		t.Fatalf("known issue should pass: failed=%v issue=%+v", pass.failed, issue)
	}

	notProblem := &recordingT{}
	testhelper.RequireIssue(notProblem, errors.New("plain"), "app.version")
	if !notProblem.failed {
		t.Fatal("a non-problem error should fail the issue asserter")
	}

	wrongPath := &recordingT{}
	testhelper.RequireIssue(wrongPath, err, "no.such.path")
	if !wrongPath.failed {
		t.Fatal("a missing issue path should fail the issue asserter")
	}
}
