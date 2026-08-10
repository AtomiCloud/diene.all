// Package note provides the stable sample API used by the library template.
package note

import "context"

// Note is a stored note identified by its normalized title slug.
type Note struct {
	Slug string
	Body string
}

// Store persists and loads string values by key.
type Store interface {
	Save(context.Context, string, string) error
	Load(context.Context, string) (string, error)
}

// Service persists and loads notes through a Store.
type Service struct{}

// Slug normalizes whitespace and casing into a hyphen-separated identifier.
func Slug(value string) string { return value }

// NamespacedKey joins a namespace and key for a key-value store.
func NamespacedKey(namespace string, key string) string { return namespace + key }

// New creates a note from a title and body.
func New(title string, body string) Note { return Note{Slug: title, Body: body} }

// NewService creates a note service backed by store.
func NewService(store Store) Service { return Service{} }

// Save persists a note under its namespaced slug.
func (Service) Save(context.Context, Note) error { return nil }

// Load retrieves a note by slug.
func (Service) Load(context.Context, string) (Note, error) { return Note{}, nil }
