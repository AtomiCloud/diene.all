package config

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"strings"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
	tekuri "github.com/santhosh-tekuri/jsonschema/v6"
	"golang.org/x/text/language"
	"golang.org/x/text/message"
)

// rootIssuePath labels an issue that applies to the whole document rather than a
// nested field.
const rootIssuePath = "(root)"

// Issue is a single, human-readable schema-validation failure: the dotted path
// of the offending value and the reason it was rejected.
type Issue struct {
	// Path is the dotted instance location, e.g. "app.landscape", or "(root)".
	Path string
	// Message explains why the value at Path is invalid.
	Message string
}

// String renders the issue as "path: message".
func (i Issue) String() string {
	return i.Path + ": " + i.Message
}

// WithPortal returns a copy of the schema whose validation failures mint their
// type URI from portal. A service passes its build-time service-tree portal so
// the problem type URI carries its own LPSM identity.
func (s Schema) WithPortal(portal problem.ErrorPortal) Schema {
	s.portal = portal
	return s
}

// Validate checks instance against the composed root schema exactly once. A
// schema-validation failure is returned as a problem-typed *[problem.Error]
// (validation-error, HTTP 400, recoverable) carrying the offending field paths
// and messages under data.fields. A malformed schema or an instance that cannot
// be normalized is returned as a plain wrapped error, since those are authoring
// faults rather than configuration-validation failures.
func (s Schema) Validate(instance map[string]any) error {
	compiled, err := s.compile()
	if err != nil {
		return fmt.Errorf("config: compile root schema: %w", err)
	}
	normalized, err := normalizeInstance(instance)
	if err != nil {
		return fmt.Errorf("config: normalize configuration: %w", err)
	}
	validationErr := compiled.Validate(normalized)
	if validationErr == nil {
		return nil
	}
	// santhosh-tekuri only ever returns *ValidationError from Validate, so the
	// comma-ok assertion always succeeds; the checked form keeps it total.
	detailed, _ := validationErr.(*tekuri.ValidationError)
	return s.validationProblem(collectIssues(detailed))
}

// portalOrLocal returns the schema's configured portal, defaulting to the
// client-local portal when none was set.
func (s Schema) portalOrLocal() problem.ErrorPortal {
	if s.portal.Host == "" {
		return problem.LocalErrorPortal()
	}
	return s.portal
}

// validationProblem builds the problem-typed error carrying issues as readable
// data.fields, minting the type URI from the schema's portal.
func (s Schema) validationProblem(issues []Issue) *problem.Error {
	return newValidationProblem(s.portalOrLocal(), issues)
}

// newValidationProblem constructs the shared validation-error envelope: HTTP
// 400, recoverable, with each [Issue] rendered as a {path, message} entry under
// data.fields. Both the schema validator and the loader's layer failures route
// through it so every configuration failure is one problem shape.
func newValidationProblem(portal problem.ErrorPortal, issues []Issue) *problem.Error {
	fields := make([]any, 0, len(issues))
	for _, issue := range issues {
		fields = append(fields, map[string]any{"path": issue.Path, "message": issue.Message})
	}
	problemType := problem.ValidationError()
	typeURI, err := problem.TypeURI(portal, problemType.Version, problemType.ID)
	if err != nil {
		typeURI = "about:blank"
	}
	detail := fmt.Sprintf("configuration failed schema validation with %d issue(s)", len(issues))
	envelope := problem.Problem{
		Type:        typeURI,
		Title:       problemType.Title,
		Status:      problemType.Status,
		Recoverable: problemType.Recoverable,
		Detail:      &detail,
		Data:        map[string]any{"fields": fields},
	}
	return problem.NewError(envelope)
}

// ValidationIssues recovers the readable [Issue] list from a problem-typed
// validation error produced by [Schema.Validate]. The second result reports
// whether err carried a validation problem with a fields payload.
func ValidationIssues(err error) ([]Issue, bool) {
	var problemErr *problem.Error
	if !errors.As(err, &problemErr) {
		return nil, false
	}
	raw, ok := problemErr.Problem.Data["fields"].([]any)
	if !ok {
		return nil, false
	}
	issues := make([]Issue, 0, len(raw))
	for _, item := range raw {
		field, ok := item.(map[string]any)
		if !ok {
			continue
		}
		path, _ := field["path"].(string)
		reason, _ := field["message"].(string)
		issues = append(issues, Issue{Path: path, Message: reason})
	}
	return issues, true
}

var issuePrinter = message.NewPrinter(language.English)

// collectIssues flattens a santhosh-tekuri validation error tree into leaf
// issues, one per most-specific failure.
func collectIssues(err *tekuri.ValidationError) []Issue {
	if len(err.Causes) == 0 {
		return []Issue{{
			Path:    instancePath(err.InstanceLocation),
			Message: err.ErrorKind.LocalizedString(issuePrinter),
		}}
	}
	issues := make([]Issue, 0, len(err.Causes))
	for _, cause := range err.Causes {
		issues = append(issues, collectIssues(cause)...)
	}
	return issues
}

// instancePath renders a validator instance location as a dotted path.
func instancePath(location []string) string {
	if len(location) == 0 {
		return rootIssuePath
	}
	return strings.Join(location, ".")
}

// normalizeInstance re-encodes a merged configuration map into the JSON-typed
// value tree the validator consumes, so integer and float values coerced from
// the environment validate under their schema types.
func normalizeInstance(instance map[string]any) (any, error) {
	raw, err := json.Marshal(instance)
	if err != nil {
		return nil, err
	}
	return tekuri.UnmarshalJSON(bytes.NewReader(raw))
}
