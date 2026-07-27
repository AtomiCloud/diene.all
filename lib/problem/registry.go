package problem

// Type is a versioned problem-type declaration. Version is part of the
// contract identity (C0 §2): bumping it mints a NEW problem type URI rather than
// mutating an existing one.
type Type struct {
	// ID is the stable identifier, e.g. "entity-not-found".
	ID string
	// Title is a short human-readable title.
	Title string
	// Version is the contract version segment, e.g. "v1".
	Version string
	// Status is the default HTTP status hint (0 means "no default").
	Status int
	// Recoverable reports whether the frontend may offer a retry (C0 §2/§14).
	Recoverable bool
	// DataSchema is the JSON Schema describing the `data` extension payload.
	DataSchema map[string]any
}

// DuplicateTypeError reports an attempt to register a problem id that is
// already present in a [Registry].
type DuplicateTypeError struct {
	// ID is the duplicate problem id.
	ID string
}

// Error implements the error interface.
func (e *DuplicateTypeError) Error() string {
	return "problem type already registered: " + e.ID
}

// UnknownTypeError reports a lookup for a problem id that is not
// registered.
type UnknownTypeError struct {
	// ID is the missing problem id.
	ID string
}

// Error implements the error interface.
func (e *UnknownTypeError) Error() string {
	return "no problem type registered for id: " + e.ID
}

// Registry is an enumerable registry of [Type]s bound to an
// [ErrorPortal]. The portal supplies the LPSM segments every type URI is built
// from, so a registry is the per-service×landscape source of truth the catalog
// emitter renders into Problem CR content (C0 §14).
type Registry struct {
	portal ErrorPortal
	types  map[string]Type
	order  []string
}

// NewRegistry creates a registry bound to portal, optionally
// pre-populated with types. It returns a [DuplicateTypeError] if types
// contains a repeated id.
func NewRegistry(portal ErrorPortal, types ...Type) (*Registry, error) {
	registry := &Registry{portal: portal, types: make(map[string]Type, len(types))}
	for _, problemType := range types {
		if err := registry.Register(problemType); err != nil {
			return nil, err
		}
	}
	return registry, nil
}

// Portal returns the error-portal block every type URI is built from.
func (r *Registry) Portal() ErrorPortal {
	return r.portal
}

// Register adds problemType, rejecting duplicates by id.
func (r *Registry) Register(problemType Type) error {
	if _, exists := r.types[problemType.ID]; exists {
		return &DuplicateTypeError{ID: problemType.ID}
	}
	r.types[problemType.ID] = problemType
	r.order = append(r.order, problemType.ID)
	return nil
}

// Lookup returns the type registered for id and whether it was present.
func (r *Registry) Lookup(id string) (Type, bool) {
	problemType, ok := r.types[id]
	return problemType, ok
}

// Require returns the type registered for id, or an [UnknownTypeError]
// when it is absent.
func (r *Registry) Require(id string) (Type, error) {
	problemType, ok := r.types[id]
	if !ok {
		return Type{}, &UnknownTypeError{ID: id}
	}
	return problemType, nil
}

// Entries returns the registered types in insertion order.
func (r *Registry) Entries() []Type {
	entries := make([]Type, 0, len(r.order))
	for _, id := range r.order {
		entries = append(entries, r.types[id])
	}
	return entries
}

// TypeURIFor builds the RFC 9457 `type` URI for problemType via the
// single-source builder and the registry's portal.
func (r *Registry) TypeURIFor(problemType Type) (string, error) {
	return TypeURI(r.portal, problemType.Version, problemType.ID)
}

// ValidationError is the generic 400 problem: the request body failed
// validation. It is recoverable and carries a `fields[]` payload.
func ValidationError() Type {
	return Type{
		ID:          "validation-error",
		Title:       "Validation error",
		Version:     defaultProblemVersion,
		Status:      400,
		Recoverable: true,
		DataSchema: map[string]any{
			"type": "object",
			"properties": map[string]any{
				"fields": map[string]any{
					"type": "array",
					"items": map[string]any{
						"type": "object",
						"properties": map[string]any{
							"path":    map[string]any{"type": "string"},
							"message": map[string]any{"type": "string"},
						},
						"required": []any{"path", "message"},
					},
				},
			},
			"required": []any{"fields"},
		},
	}
}

// EntityNotFound is the generic 404 problem: the referenced entity does not
// exist. It is not recoverable.
func EntityNotFound() Type {
	return Type{
		ID:          "entity-not-found",
		Title:       "Entity not found",
		Version:     defaultProblemVersion,
		Status:      404,
		Recoverable: false,
		DataSchema: map[string]any{
			"type": "object",
			"properties": map[string]any{
				"resource": map[string]any{"type": "string"},
				"id":       map[string]any{},
			},
			"required": []any{"resource"},
		},
	}
}

// Conflict is the generic 409 problem: a state conflict (duplicate, stale
// version, …). It is recoverable.
func Conflict() Type {
	return Type{
		ID:          "conflict",
		Title:       "Conflict",
		Version:     defaultProblemVersion,
		Status:      409,
		Recoverable: true,
		DataSchema: map[string]any{
			"type": "object",
			"properties": map[string]any{
				"resource": map[string]any{"type": "string"},
			},
		},
	}
}

// Unauthenticated is the generic 401 problem: the authenticated identity is
// missing or invalid. It is recoverable.
func Unauthenticated() Type {
	return Type{
		ID:          "unauthenticated",
		Title:       "Unauthenticated",
		Version:     defaultProblemVersion,
		Status:      401,
		Recoverable: true,
	}
}

// Unauthorized is the generic 403 problem: the identity is authenticated but
// lacks permission. It is not recoverable.
func Unauthorized() Type {
	return Type{
		ID:          "unauthorized",
		Title:       "Unauthorized",
		Version:     defaultProblemVersion,
		Status:      403,
		Recoverable: false,
	}
}

// InvalidJSON is the generic 400 problem: the request body was not valid JSON.
// It is recoverable.
func InvalidJSON() Type {
	return Type{
		ID:          "invalid-json",
		Title:       "Invalid JSON",
		Version:     defaultProblemVersion,
		Status:      400,
		Recoverable: true,
	}
}

// GenericProblems returns the portable v1 baseline catalog in stable order:
// validation-error, entity-not-found, conflict, unauthenticated, unauthorized,
// invalid-json. Domain problems stay in consumer services and are never part of
// this set.
func GenericProblems() []Type {
	return []Type{
		ValidationError(),
		EntityNotFound(),
		Conflict(),
		Unauthenticated(),
		Unauthorized(),
		InvalidJSON(),
	}
}

// RegisterGenerics registers the [GenericProblems] baseline set on registry,
// returning the first [DuplicateTypeError] encountered.
func RegisterGenerics(registry *Registry) error {
	for _, problemType := range GenericProblems() {
		if err := registry.Register(problemType); err != nil {
			return err
		}
	}
	return nil
}
