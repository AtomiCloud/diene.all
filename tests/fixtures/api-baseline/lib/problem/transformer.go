package problem

import (
	"errors"
	"fmt"
)

// TransformOptions configures how [FromObject] folds an arbitrary value into a
// [Problem].
type TransformOptions struct {
	// Portal builds fallback type URIs for uncatalogued problems.
	Portal ErrorPortal
	// Registry, when non-nil, is consulted for values carrying a known
	// `problemId`.
	Registry *Registry
	// DefaultStatus is the status for an uncatalogued fallback problem.
	DefaultStatus int
	// DefaultVersion is the version segment for fallback type URIs.
	DefaultVersion string
}

// DefaultTransformOptions returns options that mint fallback URIs from
// [LocalErrorPortal] with a 500 status and the v1 version segment, and no
// registry.
func DefaultTransformOptions() TransformOptions {
	return TransformOptions{
		Portal:         LocalErrorPortal(),
		DefaultStatus:  defaultProblemStatus,
		DefaultVersion: defaultProblemVersion,
	}
}

// FromObject folds value into a typed [Problem]. It never panics: the whole
// point is to guarantee a Problem for any value.
//
//   - A [Problem] value is returned unchanged.
//   - An error carrying a [Error] anywhere in its chain (via errors.As)
//     yields that error's Problem.
//   - When options.Registry recognises a `problemId` carried on a
//     map[string]any value, the registry's type/title/status/recoverable are
//     used and the value's `data` map is preserved.
//   - Otherwise an uncatalogued problem (C0 §14) is produced with the
//     [UncataloguedProblemID] fallback type.
func FromObject(value any, options TransformOptions) Problem {
	if envelope, ok := value.(Problem); ok {
		return envelope
	}
	if err, ok := value.(error); ok {
		var problemErr *Error
		if errors.As(err, &problemErr) {
			return problemErr.Problem
		}
	}
	if options.Registry != nil {
		if id := problemIDFrom(value); id != "" {
			if problemType, ok := options.Registry.Lookup(id); ok {
				return registeredProblem(options, problemType, dataFrom(value))
			}
		}
	}
	return uncataloguedProblem(value, options)
}

func registeredProblem(options TransformOptions, problemType Type, data map[string]any) Problem {
	status := problemType.Status
	if status == 0 {
		status = options.DefaultStatus
	}
	typeURI, err := options.Registry.TypeURIFor(problemType)
	if err != nil {
		typeURI = blankType
	}
	return Problem{
		Type:        typeURI,
		Title:       problemType.Title,
		Status:      status,
		Recoverable: problemType.Recoverable,
		Data:        data,
	}
}

func uncataloguedProblem(value any, options TransformOptions) Problem {
	typeURI, err := TypeURI(options.Portal, options.DefaultVersion, UncataloguedProblemID)
	if err != nil {
		typeURI = blankType
	}
	return Problem{
		Type:        typeURI,
		Title:       unexpectedProblemTitle,
		Status:      options.DefaultStatus,
		Detail:      detailFrom(value),
		Recoverable: false,
		Data:        map[string]any{},
	}
}

func problemIDFrom(value any) string {
	if fields, ok := value.(map[string]any); ok {
		if id, ok := fields["problemId"].(string); ok {
			return id
		}
	}
	return ""
}

func dataFrom(value any) map[string]any {
	if fields, ok := value.(map[string]any); ok {
		if data, ok := fields["data"].(map[string]any); ok {
			return data
		}
	}
	return map[string]any{}
}

func detailFrom(value any) string {
	switch typed := value.(type) {
	case nil:
		return ""
	case error:
		return typed.Error()
	case string:
		return typed
	default:
		return fmt.Sprint(typed)
	}
}
