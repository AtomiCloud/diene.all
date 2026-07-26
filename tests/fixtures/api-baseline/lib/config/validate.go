package config

import (
	"errors"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

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

// ValidationIssues recovers the readable [Issue] list from a problem-typed
// validation error produced by [Schema.Validate] or [Loader.Load]. The second
// result reports whether err carried a validation problem with a fields payload.
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
		path, ok := field["path"].(string)
		if !ok {
			continue
		}
		reason, ok := field["message"].(string)
		if !ok {
			continue
		}
		issues = append(issues, Issue{Path: path, Message: reason})
	}
	return issues, true
}
