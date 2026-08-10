// Package testhelper provides consumer-facing fakes for tests using the sample library.
package testhelper

import (
	"context"

	"github.com/AtomiCloud/diene.go-lib/lib/note"
)

// MemoryStore is an in-memory note store with injectable failures.
type MemoryStore struct {
	Values    map[string]string
	SaveError error
	LoadError error
}

// NewMemoryStore creates an empty in-memory store.
func NewMemoryStore() *MemoryStore {
	return &MemoryStore{Values: map[string]string{}}
}

// Save stores value at key unless SaveError is set.
func (store *MemoryStore) Save(_ context.Context, key string, value string) error {
	if store.SaveError != nil {
		return store.SaveError
	}
	store.Values[key] = value
	return nil
}

// Load retrieves key unless LoadError is set.
func (store *MemoryStore) Load(_ context.Context, key string) (string, error) {
	if store.LoadError != nil {
		return "", store.LoadError
	}
	return store.Values[key], nil
}

var _ note.Store = (*MemoryStore)(nil)
