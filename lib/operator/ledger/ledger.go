// Package ledger holds the pure R2 durable-ledger state machine: the source of
// record lives outside etcd, writes follow intent -> created -> confirmed, a CR
// delete orphans the entry (it never destroys the external record), and a
// same-coordinate reapply adopts the orphaned record back (preserving its
// external ID and secret pointer) rather than duplicate-creating. The secret path
// stored on an entry is a pointer, never a secret value.
//
// This package is pure domain: it imports no k8s.io/* or sigs.k8s.io/* packages.
// It operates over a Store port implemented by an adapter. The controller selects
// which explicit transition to run from the decision the reconcile service makes;
// every transition is idempotent and lookup-first.
package ledger

import (
	"context"
	"fmt"
)

// Coordinate keys a ledger entry with a platform/landscape/class/module tuple.
type Coordinate struct {
	Platform  string `json:"platform"`
	Landscape string `json:"landscape"`
	Class     string `json:"class"`
	Module    string `json:"module"`
}

// Key renders the deterministic external-name coordinate.
func (c Coordinate) Key() string {
	return c.Platform + "/" + c.Landscape + "/" + c.Class + "/" + c.Module
}

// Phase is the durable lifecycle state of a ledger entry.
type Phase string

// Ledger lifecycle phases.
const (
	PhaseIntent    Phase = "intent"
	PhaseCreated   Phase = "created"
	PhaseConfirmed Phase = "confirmed"
	PhaseOrphaned  Phase = "orphaned"
)

// Entry is a durable ledger record. SecretPath is a pointer to where a secret
// lives, never the secret value itself.
type Entry struct {
	Coordinate Coordinate `json:"coordinate"`
	Phase      Phase      `json:"phase"`
	ExternalID string     `json:"externalId"`
	SecretPath string     `json:"secretPath"`
}

// Store is the durable ledger backend port. It has no delete: a ledger entry is
// orphaned on CR delete, never destroyed.
type Store interface {
	Get(ctx context.Context, key string) (Entry, bool, error)
	Put(ctx context.Context, entry Entry) error
}

// Service is the pure ledger state machine over a Store.
type Service struct {
	store Store
}

// NewService constructs a ledger Service over a Store.
func NewService(store Store) Service {
	return Service{store: store}
}

// Get reads the entry for a coordinate.
func (s Service) Get(ctx context.Context, coord Coordinate) (Entry, bool, error) {
	return s.store.Get(ctx, coord.Key())
}

// Intent records intent for a missing coordinate. It is lookup-first: an existing
// entry is returned unchanged, never duplicate-created.
func (s Service) Intent(ctx context.Context, coord Coordinate, externalID, secretPath string) (Entry, error) {
	existing, ok, err := s.store.Get(ctx, coord.Key())
	if err != nil {
		return Entry{}, err
	}
	if ok {
		return existing, nil
	}
	entry := Entry{Coordinate: coord, Phase: PhaseIntent, ExternalID: externalID, SecretPath: secretPath}
	if err := s.store.Put(ctx, entry); err != nil {
		return Entry{}, err
	}
	return entry, nil
}

// Adopt reactivates an orphaned entry on a same-coordinate reapply. It preserves
// the existing external ID and secret pointer and never duplicate-creates.
func (s Service) Adopt(ctx context.Context, coord Coordinate) (Entry, error) {
	entry, ok, err := s.store.Get(ctx, coord.Key())
	if err != nil {
		return Entry{}, err
	}
	if !ok {
		return Entry{}, fmt.Errorf("ledger: cannot adopt missing entry %s", coord.Key())
	}
	if entry.Phase == PhaseOrphaned {
		entry.Phase = PhaseCreated
		if err := s.store.Put(ctx, entry); err != nil {
			return Entry{}, err
		}
	}
	return entry, nil
}

// Created records that the external and in-cluster resources now exist (intent ->
// created). It is idempotent.
func (s Service) Created(ctx context.Context, coord Coordinate) (Entry, error) {
	entry, ok, err := s.store.Get(ctx, coord.Key())
	if err != nil {
		return Entry{}, err
	}
	if !ok {
		return Entry{}, fmt.Errorf("ledger: cannot mark created missing entry %s", coord.Key())
	}
	if entry.Phase == PhaseIntent {
		entry.Phase = PhaseCreated
		if err := s.store.Put(ctx, entry); err != nil {
			return Entry{}, err
		}
	}
	return entry, nil
}

// Confirm records that the reconcile committed successfully (created -> confirmed).
func (s Service) Confirm(ctx context.Context, coord Coordinate) (Entry, error) {
	entry, ok, err := s.store.Get(ctx, coord.Key())
	if err != nil {
		return Entry{}, err
	}
	if !ok {
		return Entry{}, fmt.Errorf("ledger: cannot confirm missing entry %s", coord.Key())
	}
	// Enforce the state machine: confirm only advances created -> confirmed. A
	// confirmed entry is returned idempotently, and an orphaned entry is never
	// resurrected as confirmed (defense-in-depth against a future caller bug).
	if entry.Phase == PhaseCreated {
		entry.Phase = PhaseConfirmed
		if err := s.store.Put(ctx, entry); err != nil {
			return Entry{}, err
		}
	}
	return entry, nil
}

// Orphan marks an entry orphaned on CR delete. It never deletes the external
// record. Orphaning an absent coordinate is a no-op.
func (s Service) Orphan(ctx context.Context, coord Coordinate) error {
	entry, ok, err := s.store.Get(ctx, coord.Key())
	if err != nil {
		return err
	}
	if !ok {
		return nil
	}
	entry.Phase = PhaseOrphaned
	return s.store.Put(ctx, entry)
}
