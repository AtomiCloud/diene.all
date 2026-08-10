package testhelper

import "github.com/AtomiCloud/diene.go-config/lib/config"

// TestingT is the minimal subset of *testing.T the assertions use. Any type
// with Helper and Fatalf satisfies it, which keeps the helpers decoupled from
// the concrete testing type and unit-testable in the meta tier.
type TestingT interface {
	Helper()
	Fatalf(format string, args ...any)
}

// RequireConfig fails t when a load returned an error or a nil config, and
// returns the config on success. It is the assertion consumers use for the
// happy path; a (nil, nil) result is a failure, never a silent success.
func RequireConfig(t TestingT, cfg *config.Config, err error) *config.Config {
	t.Helper()
	if err != nil {
		t.Fatalf("config testhelper: expected a valid configuration, got error: %v", err)
		return nil
	}
	if cfg == nil {
		t.Fatalf("%s", "config testhelper: expected a configuration, got nil with no error")
		return nil
	}
	return cfg
}

// RequireLoadError fails t when a load unexpectedly succeeded, and returns the
// error on the expected failure. It is the assertion consumers use for fail-fast
// paths.
func RequireLoadError(t TestingT, cfg *config.Config, err error) error {
	t.Helper()
	if err == nil {
		t.Fatalf("config testhelper: expected a load failure, got a valid configuration: %+v", cfg)
		return nil
	}
	return err
}

// RequireIssue fails t unless err carries a problem-typed validation failure
// with an issue at wantPath, and returns that issue on success.
func RequireIssue(t TestingT, err error, wantPath string) config.Issue {
	t.Helper()
	issues, ok := config.ValidationIssues(err)
	if !ok {
		t.Fatalf("config testhelper: expected a validation problem, got: %v", err)
		return config.Issue{}
	}
	for _, issue := range issues {
		if issue.Path == wantPath {
			return issue
		}
	}
	t.Fatalf("config testhelper: no validation issue at %q; issues=%v", wantPath, issues)
	return config.Issue{}
}
