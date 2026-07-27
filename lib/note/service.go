package note

import "context"

// Store persists and loads string values by key.
type Store interface {
	Save(context.Context, string, string) error
	Load(context.Context, string) (string, error)
}

// Service persists and loads notes through a Store.
type Service struct {
	store Store
}

// NewService creates a note service backed by store.
func NewService(store Store) Service {
	return Service{store: store}
}

// Save persists a note under its namespaced slug.
func (service Service) Save(ctx context.Context, value Note) error {
	return service.store.Save(ctx, NamespacedKey("notes", value.Slug), value.Body)
}

// Load retrieves a note by slug.
func (service Service) Load(ctx context.Context, slug string) (Note, error) {
	body, err := service.store.Load(ctx, NamespacedKey("notes", slug))
	if err != nil {
		return Note{}, err
	}
	return Note{Slug: slug, Body: body}, nil
}
