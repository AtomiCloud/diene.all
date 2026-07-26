// Package valid compiles a composed JSON Schema, normalizes a configuration
// instance, validates it, and renders failures as problem-typed errors. It is
// an internal package with an exported, black-box-testable API, not part of the
// public config surface.
package valid

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"strings"

	"github.com/AtomiCloud/diene.go-config/lib/config/internal/collision"
	"github.com/AtomiCloud/diene.go-config/lib/config/internal/schemaview"
	"github.com/AtomiCloud/diene.go-core-utils/lib/coreutils"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
	tekuri "github.com/santhosh-tekuri/jsonschema/v6"
	"golang.org/x/text/language"
	"golang.org/x/text/message"
)

// rootPath labels an issue that applies to the whole document rather than a
// nested field.
const rootPath = "(root)"

// schemaResourceURL is the in-memory resource id the composed root schema is
// registered under before compilation. It never leaves the process.
const schemaResourceURL = "https://diene.atomi.cloud/config/root.schema.json"

// issuePrinter renders validator error kinds in English.
var issuePrinter = message.NewPrinter(language.English)

// Issue is a single, human-readable schema-validation failure.
type Issue struct {
	// Path is the dotted instance location, e.g. "app.landscape", or "(root)".
	Path string
	// Message explains why the value at Path is invalid.
	Message string
}

// Compile marshals a composed root schema map and compiles it with
// santhosh-tekuri/jsonschema, asserting formats and registering the C0 wire
// formats so a schema can reject malformed temporal values. A malformed
// fragment surfaces here.
func Compile(root map[string]any) (*tekuri.Schema, error) {
	raw, marshalErr := json.Marshal(root)
	document, decodeErr := tekuri.UnmarshalJSON(bytes.NewReader(raw))
	compiler := tekuri.NewCompiler()
	compiler.AssertFormat()
	for _, format := range WireFormats() {
		compiler.RegisterFormat(format)
	}
	addErr := compiler.AddResource(schemaResourceURL, document)
	if joined := errors.Join(marshalErr, decodeErr, addErr); joined != nil {
		return nil, joined
	}
	return compiler.Compile(schemaResourceURL)
}

// WireFormats returns the C0 wire-format assertions — wire-date, wire-time,
// iso-duration, iana-time-zone, and rfc3339-utc — backed by the published
// core-utils parsers, so a schema rejects malformed temporal values rather than
// accepting any string. rfc3339-utc enforces the strict UTC millisecond instant
// (offsets and naive instants are rejected).
func WireFormats() []*tekuri.Format {
	return []*tekuri.Format{
		StringFormat("wire-date", func(text string) error { _, err := coreutils.ParseWireDate(text); return err }),
		StringFormat("wire-time", func(text string) error { _, err := coreutils.ParseWireTime(text); return err }),
		StringFormat("iso-duration", func(text string) error { _, err := coreutils.ParseIsoDuration(text); return err }),
		StringFormat("rfc3339-utc", func(text string) error { _, err := coreutils.ParseRFC3339UTC(text); return err }),
		StringFormat("iana-time-zone", func(text string) error {
			if !coreutils.IsIanaTimezone(text) {
				return fmt.Errorf("expected an IANA timezone identifier: %q", text)
			}
			return nil
		}),
	}
}

// StringFormat builds a santhosh-tekuri format that applies check to string
// values and skips non-strings, so a format assertion never rejects a value of
// the wrong type (that is the type keyword's job).
func StringFormat(name string, check func(string) error) *tekuri.Format {
	return &tekuri.Format{Name: name, Validate: func(value any) error {
		text, ok := value.(string)
		if !ok {
			return nil
		}
		return check(text)
	}}
}

// Normalize re-encodes a merged configuration map into the JSON-typed value tree
// the validator consumes, so integer and float values coerced from the
// environment validate under their schema types.
func Normalize(instance map[string]any) (any, error) {
	raw, err := json.Marshal(instance)
	if err != nil {
		return nil, err
	}
	return tekuri.UnmarshalJSON(bytes.NewReader(raw))
}

// Collect flattens a santhosh-tekuri validation error tree into leaf issues, one
// per most-specific failure.
func Collect(node *tekuri.ValidationError) []Issue {
	if len(node.Causes) == 0 {
		return []Issue{{
			Path:    Path(node.InstanceLocation),
			Message: node.ErrorKind.LocalizedString(issuePrinter),
		}}
	}
	issues := make([]Issue, 0, len(node.Causes))
	for _, cause := range node.Causes {
		issues = append(issues, Collect(cause)...)
	}
	return issues
}

// Path renders a validator instance location as a dotted path.
func Path(location []string) string {
	if len(location) == 0 {
		return rootPath
	}
	return strings.Join(location, ".")
}

// EnvIssue maps an environment coercion failure to an issue keyed by the
// offending environment key, falling back to a generic environment path.
func EnvIssue(cause error) Issue {
	issue := Issue{Path: "(environment)", Message: cause.Error()}
	var coercion *coreutils.EnvironmentCoercionError
	if errors.As(cause, &coercion) {
		issue = Issue{Path: coercion.Key, Message: coercion.Reason}
	}
	return issue
}

// Problem builds the shared validation-error envelope: HTTP 400, recoverable,
// with each issue rendered as a {path, message} entry under data.fields. A zero
// portal falls back to the client-local portal.
func Problem(portal problem.ErrorPortal, issues []Issue) *problem.Error {
	if portal.Host == "" {
		portal = problem.LocalErrorPortal()
	}
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

// Evaluate normalizes schemaRoot into one generic JSON document, compiles it,
// rejects canonical property collisions, aligns and normalizes instance, and
// validates it exactly once. Normalizing first is what keeps compilation,
// collision detection, and alignment on exactly the SAME document, so a typed
// authoring container (map[string]map[string]any) or a local $ref cannot bypass
// the canonical-key contract. A schema-validation failure is returned as a
// problem-typed error; a cyclic, unencodable, or malformed schema and an
// unencodable instance are plain wrapped errors.
func Evaluate(schemaRoot map[string]any, portal problem.ErrorPortal, instance map[string]any) error {
	// Normalizing marshals the schema, so a cyclic authoring fault surfaces here
	// (json.Marshal rejects it) before anything walks the document.
	normalizedSchema, err := schemaview.Normalize(schemaRoot)
	if err != nil {
		return fmt.Errorf("config: normalize root schema: %w", err)
	}
	document := schemaview.NewDocument(normalizedSchema)
	compiled, err := Compile(normalizedSchema)
	if err != nil {
		return fmt.Errorf("config: compile root schema: %w", err)
	}
	if location, detail, collided := document.Collision(); collided {
		return fmt.Errorf("config: schema property collision at %s: %s", location, detail)
	}
	normalized, err := Normalize(instance)
	if err != nil {
		return fmt.Errorf("config: normalize configuration: %w", err)
	}
	// Collision detection and key alignment run on the normalized JSON object so
	// typed containers (map[string]string, typed slices) are already flattened to
	// map[string]any / []any and their aliases cannot be missed.
	//nolint:revive // a normalized configuration object is always a map.
	object, _ := normalized.(map[string]any)
	if location, detail, collided := collision.Detect(object); collided {
		return Problem(portal, []Issue{{Path: location, Message: detail}})
	}
	validationErr := compiled.Validate(document.Align(schemaview.Position{document.Root()}, object))
	if validationErr == nil {
		return nil
	}
	// santhosh-tekuri only ever returns *ValidationError from Validate, so
	// errors.As always populates detailed; the bool is intentionally discarded.
	var detailed *tekuri.ValidationError
	_ = errors.As(validationErr, &detailed)
	return Problem(portal, Collect(detailed))
}
