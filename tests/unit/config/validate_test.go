package config_test

import (
	"errors"
	"testing"

	"github.com/AtomiCloud/diene.go-config/lib/config"
	"github.com/AtomiCloud/diene.go-config/testhelper"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
	problemtest "github.com/AtomiCloud/diene.go-errors-problems/testhelper"
)

func validInstance() map[string]any {
	return map[string]any{
		"app": map[string]any{
			"landscape": "lapras", "platform": "sulfoxide",
			"service": "config", "module": "lib", "version": "1.0.0",
		},
		"demo": map[string]any{"region": "local"},
	}
}

func TestValidateAcceptsAValidInstance(t *testing.T) {
	t.Parallel()
	if err := testhelper.Schema().Validate(validInstance()); err != nil {
		t.Fatalf("valid instance must pass: %v", err)
	}
}

func TestValidateRejectsWithProblemTypedError(t *testing.T) {
	t.Parallel()
	instance := validInstance()
	instance["app"].(map[string]any)["version"] = ""
	delete(instance["demo"].(map[string]any), "region")

	err := testhelper.Schema().Validate(instance)
	// The failure is compatible with errors.As to *problem.Error, is the
	// validation-error catalog member, and is HTTP 400 recoverable.
	envelope := problemtest.AssertError(
		t, err,
		problemtest.ExpectID("validation-error"),
		problemtest.ExpectStatus(400),
		problemtest.ExpectRecoverable(true),
	)
	fields, ok := envelope.Data["fields"].([]any)
	if !ok || len(fields) == 0 {
		t.Fatalf("problem must carry readable fields: %v", envelope.Data)
	}
	issues, ok := config.ValidationIssues(err)
	if !ok || len(issues) < 2 {
		t.Fatalf("expected multiple issues, got %v", issues)
	}
}

func TestValidateSurfacesNestedIssuePaths(t *testing.T) {
	t.Parallel()
	instance := validInstance()
	instance["app"].(map[string]any)["version"] = ""
	err := testhelper.Schema().Validate(instance)
	if _, found := testhelperIssueAt(config.ValidationIssues(err)); !found {
		t.Fatalf("expected an app.version issue, got %v", err)
	}
}

func testhelperIssueAt(issues []config.Issue, _ bool) (config.Issue, bool) {
	for _, issue := range issues {
		if issue.Path == "app.version" {
			return issue, true
		}
	}
	return config.Issue{}, false
}

func TestValidateReportsCompileFaultAsPlainError(t *testing.T) {
	t.Parallel()
	schema := config.ComposeSchema(testhelper.InvalidSchemaBlock())
	err := schema.Validate(validInstance())
	if err == nil {
		t.Fatal("an uncompilable schema must error")
	}
	if _, ok := config.ValidationIssues(err); ok {
		t.Fatal("a schema-authoring fault is not a validation problem")
	}
}

func TestValidateReportsNormalizeFaultAsPlainError(t *testing.T) {
	t.Parallel()
	// A value that cannot be JSON-encoded is an authoring fault, not a
	// configuration-validation failure.
	err := testhelper.Schema().Validate(map[string]any{"demo": make(chan int)})
	if err == nil {
		t.Fatal("an unencodable instance must error")
	}
	if _, ok := config.ValidationIssues(err); ok {
		t.Fatal("a normalize fault is not a validation problem")
	}
}

func TestValidateWithInvalidPortalFallsBackToBlankType(t *testing.T) {
	t.Parallel()
	// A portal whose landscape segment is invalid cannot mint a type URI, so the
	// problem falls back to about:blank rather than failing to report.
	schema := testhelper.Schema().WithPortal(problem.ErrorPortal{
		Scheme: "https", Host: "docs.example", Landscape: "bad/segment",
		Platform: "go", Service: "config", Module: "lib",
	})
	instance := validInstance()
	instance["app"].(map[string]any)["version"] = ""
	err := schema.Validate(instance)
	var problemErr *problem.Error
	if !errors.As(err, &problemErr) {
		t.Fatalf("expected a problem error, got %v", err)
	}
	if problemErr.Problem.Type != "about:blank" {
		t.Fatalf("invalid portal must fall back to about:blank, got %q", problemErr.Problem.Type)
	}
}

func TestValidateUsesConfiguredPortalIdentity(t *testing.T) {
	t.Parallel()
	schema := testhelper.Schema().WithPortal(problemtest.SampleErrorPortal())
	instance := validInstance()
	instance["app"].(map[string]any)["version"] = ""
	err := schema.Validate(instance)
	var problemErr *problem.Error
	if !errors.As(err, &problemErr) {
		t.Fatalf("expected a problem error, got %v", err)
	}
	if problemErr.Problem.Status != 400 {
		t.Fatalf("expected 400, got %d", problemErr.Problem.Status)
	}
}

func TestValidationIssuesRejectsNonProblemError(t *testing.T) {
	t.Parallel()
	if _, ok := config.ValidationIssues(errors.New("plain")); ok {
		t.Fatal("a plain error carries no validation issues")
	}
}

func TestValidationIssuesRejectsProblemWithoutFields(t *testing.T) {
	t.Parallel()
	err := problem.NewError(problem.Problem{Data: map[string]any{"other": 1}})
	if _, ok := config.ValidationIssues(err); ok {
		t.Fatal("a problem without a fields payload carries no issues")
	}
}

func TestValidationIssuesSkipsMalformedFieldEntries(t *testing.T) {
	t.Parallel()
	err := problem.NewError(problem.Problem{Data: map[string]any{
		"fields": []any{
			"not-a-map",
			map[string]any{"path": 123, "message": "required"},
			map[string]any{"path": "app.module", "message": 456},
			map[string]any{"path": "app.version", "message": "required"},
		},
	}})
	issues, ok := config.ValidationIssues(err)
	if !ok || len(issues) != 1 || issues[0].Path != "app.version" {
		t.Fatalf("malformed entries must be skipped: %v", issues)
	}
}

func TestIssueStringForm(t *testing.T) {
	t.Parallel()
	issue := config.Issue{Path: "app.version", Message: "required"}
	if issue.String() != "app.version: required" {
		t.Fatalf("unexpected issue string: %q", issue.String())
	}
}
