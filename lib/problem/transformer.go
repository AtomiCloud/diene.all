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
		// errors.As also succeeds for a typed-nil *Error (a non-nil error
		// interface holding a nil pointer). Dereferencing that as a Problem —
		// or letting it fall through to detailFrom, whose Error() call would
		// dereference nil — panics, so treat it as an empty uncatalogued value.
		var problemErr *Error
		if errors.As(err, &problemErr) {
			if problemErr != nil {
				return problemErr.Problem
			}
			value = nil
		}
	}
	if options.Registry != nil {
		if fields, ok := value.(map[string]any); ok {
			if id, ok := fields["problemId"].(string); ok && id != "" {
				if problemType, found := options.Registry.Lookup(id); found {
					status := problemType.Status
					if status == 0 {
						status = options.DefaultStatus
					}
					typeURI, typeErr := options.Registry.TypeURIFor(problemType)
					if typeErr != nil {
						typeURI = blankType
					}
					problemData, dataOK := fields["data"].(map[string]any)
					if !dataOK {
						problemData = map[string]any{}
					}
					return Problem{
						Type:        typeURI,
						Title:       problemType.Title,
						Status:      status,
						Recoverable: problemType.Recoverable,
						Data:        problemData,
					}
				}
			}
		}
	}
	typeURI, err := TypeURI(options.Portal, options.DefaultVersion, UncataloguedProblemID)
	if err != nil {
		typeURI = blankType
	}
	var detail *string
	text := ""
	switch typed := value.(type) {
	case nil:
	case error:
		text = typed.Error()
	case string:
		text = typed
	default:
		text = fmt.Sprint(typed)
	}
	if text != "" {
		detail = &text
	}
	return Problem{
		Type:        typeURI,
		Title:       unexpectedProblemTitle,
		Status:      options.DefaultStatus,
		Detail:      detail,
		Recoverable: false,
		Data:        map[string]any{},
	}
}
