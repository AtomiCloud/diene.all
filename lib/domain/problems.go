package domain

import (
	"errors"
	"fmt"
	"strings"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

const MessageHandlerFailedID = "message_handler_failed"

// Problems is the service-owned problem registry and exported catalog.
type Problems struct {
	registry *problem.Registry
	catalog  *problem.Catalog
}

// MessageHandlerProblem describes failures in the sample consume handler.
func MessageHandlerProblem(version string) problem.Type {
	return problem.Type{
		ID:          MessageHandlerFailedID,
		Title:       "Message handler failed",
		Version:     version,
		Status:      500,
		Recoverable: true,
		DataSchema: map[string]any{
			"type":                 "object",
			"additionalProperties": false,
			"required":             []any{"messageId", "stage"},
			"properties": map[string]any{
				"messageId": map[string]any{"type": "string", "minLength": 1},
				"stage":     map[string]any{"type": "string", "minLength": 1},
			},
		},
	}
}

// NewProblems builds the generic and domain problem registry and catalog.
func NewProblems(
	portal problem.ErrorPortal,
	stream string,
	version string,
	extra ...problem.Type,
) (*Problems, error) {
	if strings.TrimSpace(stream) == "" {
		return nil, setupError(errors.New("problem stream must not be blank"))
	}
	if !validProblemVersion(version) {
		return nil, setupError(fmt.Errorf("problem version %q must match v<digits>", version))
	}
	handlerType := MessageHandlerProblem(version)
	types := append(problem.GenericProblems(), handlerType)
	types = append(types, extra...)
	registry, err := problem.NewRegistry(portal, types...)
	if err != nil {
		return nil, setupError(err)
	}
	catalog := problem.NewCatalog(portal)
	if err := catalog.AddType(handlerType, problem.CatalogEndpoint{
		Method: "CONSUME",
		Path:   "/streams/" + strings.TrimSpace(stream),
	}); err != nil {
		return nil, setupError(err)
	}
	for _, problemType := range extra {
		if err := catalog.AddType(problemType); err != nil {
			return nil, setupError(err)
		}
	}
	return &Problems{registry: registry, catalog: catalog}, nil
}

// Registry returns the service registry used to mint runtime errors.
func (problems *Problems) Registry() *problem.Registry {
	return problems.registry
}

// Catalog returns the service catalog used by the primordial problem export.
func (problems *Problems) Catalog() *problem.Catalog {
	return problems.catalog
}

// RaiseHandler wraps cause as the cataloged handler problem.
func (problems *Problems) RaiseHandler(messageID, stage, detail string, cause error) error {
	if cause == nil {
		cause = errors.New(detail)
	}
	return raiseHandler(problems.registry, messageID, stage, detail, cause)
}

// raiseConstructionFault reports a handler that cannot be constructed. It uses the
// LOCAL portal deliberately: construction fails before the service catalog is
// available, so there is no configured registry to raise through yet.
func raiseConstructionFault(detail string, cause error) error {
	registry, _ := problem.NewRegistry(problem.LocalErrorPortal(), MessageHandlerProblem("v1"))
	return raiseHandler(registry, "constructor", "construction", detail, cause)
}

func raiseHandler(registry *problem.Registry, messageID, stage, detail string, cause error) error {
	options := problem.DefaultTransformOptions()
	options.Registry = registry
	envelope := problem.FromObject(map[string]any{
		"problemId": MessageHandlerFailedID,
		"data":      map[string]any{"messageId": messageID, "stage": stage},
	}, options)
	envelope.Detail = &detail
	return problem.WrapError(envelope, cause)
}

func setupError(cause error) error {
	envelope := problem.FromObject(cause, problem.DefaultTransformOptions())
	return problem.WrapError(envelope, cause)
}

func validProblemVersion(version string) bool {
	if len(version) < 2 || version[0] != 'v' {
		return false
	}
	for _, character := range version[1:] {
		if character < '0' || character > '9' {
			return false
		}
	}
	return true
}
