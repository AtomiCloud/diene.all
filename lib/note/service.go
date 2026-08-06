package note

// DOMAIN WIRING: replaceable Note sample service over the KV port.
import "context"

type Store interface {
	Save(context.Context, string, string) error
	Load(context.Context, string) (string, error)
}

type Service struct {
	store Store
}

func NewService(store Store) Service {
	return Service{store: store}
}

func (service Service) Save(ctx context.Context, value Note) error {
	return service.store.Save(ctx, NamespacedKey("notes", value.Slug), value.Body)
}

func (service Service) Load(ctx context.Context, slug string) (Note, error) {
	body, err := service.store.Load(ctx, NamespacedKey("notes", slug))
	if err != nil {
		return Note{}, err
	}
	return Note{Slug: slug, Body: body}, nil
}

// END DOMAIN WIRING
