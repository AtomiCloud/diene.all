// Package testhelper provides the stable consumer-facing fake API.
package testhelper

import "context"

// MemoryStore is an in-memory note store with injectable failures.
type MemoryStore struct {
	Values    map[string]string
	SaveError error
	LoadError error
}

// NewMemoryStore creates an empty in-memory store.
func NewMemoryStore() *MemoryStore { return &MemoryStore{} }

// Save stores value at key unless SaveError is set.
func (*MemoryStore) Save(context.Context, string, string) error { return nil }

// Load retrieves key unless LoadError is set.
func (*MemoryStore) Load(context.Context, string) (string, error) { return "", nil }
