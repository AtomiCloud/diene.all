// Package ledger holds the pure R2 durable-ledger state machine: the source of
// record lives outside etcd, writes follow intent -> create -> confirm, a CR
// delete orphans the entry (it never destroys the external record), and recovery
// is ledger-lookup-first (find-or-adopt, never duplicate-create). The secret
// path stored on an entry is a pointer, never a secret value.
//
// This package is pure domain: it imports no k8s.io/* or sigs.k8s.io/* packages.
// It operates over a Store port implemented by an adapter.
package ledger

import "context"

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

// Reserve records intent for a coordinate. It is lookup-first: an existing entry
// is adopted back and returned unchanged rather than duplicate-created.
func (s Service) Reserve(ctx context.Context, coord Coordinate, externalID, secretPath string) (Entry, error) {
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

// Advance moves an existing entry from intent to created to confirmed. Reserving
// an absent coordinate first is required; Advance on a missing entry is a no-op
// that reports found=false.
func (s Service) Advance(ctx context.Context, coord Coordinate) (Entry, bool, error) {
	entry, ok, err := s.store.Get(ctx, coord.Key())
	if err != nil {
		return Entry{}, false, err
	}
	if !ok {
		return Entry{}, false, nil
	}
	entry.Phase = next(entry.Phase)
	if err := s.store.Put(ctx, entry); err != nil {
		return Entry{}, false, err
	}
	return entry, true, nil
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

func next(phase Phase) Phase {
	if phase == PhaseIntent {
		return PhaseCreated
	}
	if phase == PhaseCreated {
		return PhaseConfirmed
	}
	return phase
}
