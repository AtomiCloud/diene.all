// Package ledger holds the pure R2 durable-ledger state machine. The source of
// record lives outside etcd; writes follow intent -> created -> confirmed; CR
// deletion only orphans; spec removal tombstones after proof; and physical
// deletion is available only to an explicitly purge-capable Decommission flow.
// Ledger entries contain secret pointers, never secret values.
//
// This package is pure domain: it imports no Kubernetes packages. Time is
// supplied by callers of the strict service so every transition is deterministic.
package ledger

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/AtomiCloud/diene.go-core-utils/lib/coreutils"
)

// SecretRetainGrace is the mandatory retain intent recorded when a module is
// removed from a specification.
const SecretRetainGrace = 168 * time.Hour

// Stable error categories. Concrete coordinate, transition, and generation
// errors unwrap to these values so callers can use errors.Is and errors.As.
var (
	ErrInvalidCoordinate     = errors.New("ledger: invalid coordinate")
	ErrInvalidIntent         = errors.New("ledger: invalid intent")
	ErrMissingEntry          = errors.New("ledger: missing entry")
	ErrInvalidTransition     = errors.New("ledger: invalid transition")
	ErrStaleGeneration       = errors.New("ledger: stale generation")
	ErrInvalidTombstoneProof = errors.New("ledger: invalid tombstone proof")
	ErrInvalidPurgePermit    = errors.New("ledger: invalid purge permit")
	ErrPurgeUnavailable      = errors.New("ledger: purge capability unavailable")
	ErrStrictServiceRequired = errors.New("ledger: strict service required")
	ErrInvalidService        = errors.New("ledger: invalid service")
	ErrInvalidTimestamp      = errors.New("ledger: invalid timestamp")
)

// Coordinate keys a dependency ledger entry. Every segment is mandatory and
// account is never inferred: external identifiers are unique only within the
// composite (vendor, account) scope.
type Coordinate struct {
	Platform  string `json:"platform"`
	Landscape string `json:"landscape"`
	Class     string `json:"class"`
	Module    string `json:"module"`
	Vendor    string `json:"vendor"`
	Account   string `json:"account"`
}

// NewCoordinate validates and constructs a six-segment ledger coordinate.
func NewCoordinate(platform, landscape, class, module, vendor, account string) (Coordinate, error) {
	coordinate := Coordinate{
		Platform: platform, Landscape: landscape, Class: class,
		Module: module, Vendor: vendor, Account: account,
	}
	if err := coordinate.Validate(); err != nil {
		return Coordinate{}, err
	}
	return coordinate, nil
}

// Validate rejects blank or slash-containing key segments.
func (c Coordinate) Validate() error {
	segments := []struct {
		name  string
		value string
	}{
		{name: "platform", value: c.Platform},
		{name: "landscape", value: c.Landscape},
		{name: "class", value: c.Class},
		{name: "module", value: c.Module},
		{name: "vendor", value: c.Vendor},
		{name: "account", value: c.Account},
	}
	for _, segment := range segments {
		if strings.TrimSpace(segment.value) == "" {
			return &CoordinateError{Segment: segment.name, Value: segment.value, Reason: "must be nonblank"}
		}
		if strings.Contains(segment.value, "/") {
			return &CoordinateError{Segment: segment.name, Value: segment.value, Reason: "must be one path segment"}
		}
	}
	return nil
}

// Key renders the exact deterministic ledger key.
func (c Coordinate) Key() string {
	return c.Platform + "/" + c.Landscape + "/" + c.Class + "/" + c.Module + "/" + c.Vendor + "/" + c.Account
}

// CoordinateError describes the invalid segment without losing its field name.
type CoordinateError struct {
	Segment string
	Value   string
	Reason  string
}

// Error implements error.
func (e *CoordinateError) Error() string {
	return fmt.Sprintf("%s: %s segment %q %s", ErrInvalidCoordinate, e.Segment, e.Value, e.Reason)
}

// Unwrap exposes ErrInvalidCoordinate.
func (*CoordinateError) Unwrap() error { return ErrInvalidCoordinate }

// Phase is the durable lifecycle state of a ledger entry.
type Phase string

// Ledger lifecycle phases. Purge is deliberately not a phase: it is physical
// deletion protected by a separate capability and typed permit.
const (
	PhaseIntent     Phase = "intent"
	PhaseCreated    Phase = "created"
	PhaseConfirmed  Phase = "confirmed"
	PhaseOrphaned   Phase = "orphaned"
	PhaseTombstoned Phase = "tombstoned"
)

// Timestamps is the additive UTC wire-time envelope for an Entry. Empty fields
// are absent historical facts, which keeps old four-field JSON entries readable.
type Timestamps struct {
	CreatedAt    string `json:"createdAt,omitempty"`
	UpdatedAt    string `json:"updatedAt,omitempty"`
	OrphanedAt   string `json:"orphanedAt,omitempty"`
	TombstonedAt string `json:"tombstonedAt,omitempty"`
	RetainUntil  string `json:"retainUntil,omitempty"`
}

// Entry is the additive durable record schema. SecretPath is a reference to a
// secret location, never a credential, token, password, connection payload, or
// other secret value.
type Entry struct {
	Coordinate      Coordinate `json:"coordinate"`
	Phase           Phase      `json:"phase"`
	ExternalID      string     `json:"externalId"`
	Vendor          string     `json:"vendor"`
	Account         string     `json:"account"`
	Region          string     `json:"region"`
	SecretPath      string     `json:"secretPath"`
	Generation      int64      `json:"generation"`
	LastAppliedHash string     `json:"lastAppliedHash"`
	Timestamps      Timestamps `json:"timestamps"`
}

// Store is the ordinary durable backend port. It intentionally remains the
// original two-method interface so reconciliation fakes do not gain destructive
// authority.
type Store interface {
	Get(ctx context.Context, key string) (Entry, bool, error)
	Put(ctx context.Context, entry Entry) error
}

// PurgeStore is the separate destructive capability wired only into an
// authorized Decommission flow.
type PurgeStore interface {
	Purge(ctx context.Context, key string) error
}

// TransitionError identifies a rejected operation, coordinate, and source
// phase. Cause is either ErrMissingEntry or ErrInvalidTransition.
type TransitionError struct {
	Coordinate Coordinate
	Operation  string
	From       Phase
	Cause      error
}

// Error implements error.
func (e *TransitionError) Error() string {
	return fmt.Sprintf("ledger: cannot %s entry %s from phase %q: %v", e.Operation, e.Coordinate.Key(), e.From, e.Cause)
}

// Unwrap exposes the stable transition category.
func (e *TransitionError) Unwrap() error { return e.Cause }

// GenerationError identifies an attempted rollback of a stored generation.
type GenerationError struct {
	Coordinate Coordinate
	Stored     int64
	Attempted  int64
}

// Error implements error.
func (e *GenerationError) Error() string {
	return fmt.Sprintf("%s: entry %s stores generation %d, attempted %d", ErrStaleGeneration, e.Coordinate.Key(), e.Stored, e.Attempted)
}

// Unwrap exposes ErrStaleGeneration.
func (*GenerationError) Unwrap() error { return ErrStaleGeneration }

// IntentSpec is the complete strict intent input. LastApplied is canonical-JSON
// hashed before persistence; the value itself is never written to the ledger.
type IntentSpec struct {
	ExternalID  string
	Region      string
	SecretPath  string
	Generation  int64
	LastApplied any
}

type lastAppliedHashMode uint8

const (
	omitLastAppliedHash lastAppliedHashMode = iota
	computeLastAppliedHash
)

// TombstoneProof can be constructed only after all three spec-removal
// assertions have been supplied. Its zero value is invalid.
type TombstoneProof struct{ complete bool }

// NewTombstoneProof validates snapshot, vendor deletion, and 168-hour retain
// intent assertions.
func NewTombstoneProof(snapshotted, vendorDeleted, retainIntentRecorded bool) (TombstoneProof, error) { //nolint:revive // each boolean is an independently required proof assertion
	if !snapshotted {
		return TombstoneProof{}, fmt.Errorf("%w: final backup snapshot is required", ErrInvalidTombstoneProof)
	}
	if !vendorDeleted {
		return TombstoneProof{}, fmt.Errorf("%w: vendor deletion is required", ErrInvalidTombstoneProof)
	}
	if !retainIntentRecorded {
		return TombstoneProof{}, fmt.Errorf("%w: 168h secret-retain intent is required", ErrInvalidTombstoneProof)
	}
	return TombstoneProof{complete: true}, nil
}

// PurgePermit can be constructed only after the Decommission condition ladder
// and target authorization have all been supplied. Its zero value is invalid.
type PurgePermit struct{ complete bool }

// NewPurgePermit validates the four assertions required for physical deletion.
func NewPurgePermit(refsClear, snapshotted, externalsDeleted, targetAuthorized bool) (PurgePermit, error) { //nolint:revive // each boolean is an independently required permit assertion
	if !refsClear {
		return PurgePermit{}, fmt.Errorf("%w: references-clear proof is required", ErrInvalidPurgePermit)
	}
	if !snapshotted {
		return PurgePermit{}, fmt.Errorf("%w: snapshot proof is required", ErrInvalidPurgePermit)
	}
	if !externalsDeleted {
		return PurgePermit{}, fmt.Errorf("%w: externals-deleted proof is required", ErrInvalidPurgePermit)
	}
	if !targetAuthorized {
		return PurgePermit{}, fmt.Errorf("%w: target authorization is required", ErrInvalidPurgePermit)
	}
	return PurgePermit{complete: true}, nil
}

// Service is the pure ledger state machine over a Store.
type Service struct {
	store   Store
	purge   PurgeStore
	now     func() time.Time
	lenient bool
}

// NewService preserves the inherited compatibility facade. It uses the strict
// transition engine with leniency only for the two historically out-of-order
// Created/Confirm calls, and deliberately records no timestamps because the old
// API has no clock seam. Coordinates are still fully validated.
func NewService(store Store) Service {
	return Service{store: store, lenient: true}
}

// NewStrictService constructs the product service with a deterministic clock
// and without destructive authority.
func NewStrictService(store Store, now func() time.Time) (Service, error) {
	if store == nil {
		return Service{}, fmt.Errorf("%w: store is required", ErrInvalidService)
	}
	if now == nil {
		return Service{}, fmt.Errorf("%w: clock is required", ErrInvalidService)
	}
	return Service{store: store, now: now}, nil
}

// NewStrictPurgeService constructs the only service shape capable of physical
// ledger deletion. Purge still requires a valid typed permit per call.
func NewStrictPurgeService(store Store, purge PurgeStore, now func() time.Time) (Service, error) {
	service, err := NewStrictService(store, now)
	if err != nil {
		return Service{}, err
	}
	if purge == nil {
		return Service{}, fmt.Errorf("%w: purge store is required", ErrInvalidService)
	}
	service.purge = purge
	return service, nil
}

// FormatTimestamp normalizes an instant to UTC and preserves all available
// fractional precision with RFC3339Nano.
func FormatTimestamp(value time.Time) (string, error) {
	utc := value.UTC()
	if utc.Year() < 1 || utc.Year() > 9999 {
		return "", fmt.Errorf("%w: year %d is outside RFC3339", ErrInvalidTimestamp, utc.Year())
	}
	return utc.Format(time.RFC3339Nano), nil
}

// ParseTimestamp validates a strict UTC RFC3339 instant, including nanosecond
// precision, through the published core-utils temporal codec.
func ParseTimestamp(value string) (time.Time, error) {
	instant, err := coreutils.ParseRFC3339UTC(value)
	if err != nil {
		return time.Time{}, fmt.Errorf("%w: %w", ErrInvalidTimestamp, err)
	}
	return instant, nil
}

// Get reads the entry for a validated coordinate.
func (s Service) Get(ctx context.Context, coordinate Coordinate) (Entry, bool, error) {
	return s.load(ctx, coordinate)
}

// Intent is the inherited facade entry point. A missing coordinate receives a
// reduced intent; an existing coordinate is returned unchanged lookup-first.
func (s Service) Intent(ctx context.Context, coordinate Coordinate, externalID, secretPath string) (Entry, error) {
	spec := IntentSpec{
		ExternalID: externalID,
		SecretPath: secretPath,
		LastApplied: struct {
			ExternalID string `json:"externalId"`
			SecretPath string `json:"secretPath"`
		}{ExternalID: externalID, SecretPath: secretPath},
	}
	hashMode := omitLastAppliedHash
	if !s.lenient {
		hashMode = computeLastAppliedHash
	}
	return s.recordIntent(ctx, coordinate, spec, hashMode)
}

// IntentWithSpec records a complete strict intent. Existing entries are returned
// unchanged; on a miss, the last-applied value is hashed with coreutils.StableHash.
func (s Service) IntentWithSpec(ctx context.Context, coordinate Coordinate, spec IntentSpec) (Entry, error) {
	if err := s.requireStrict("record full intent"); err != nil {
		return Entry{}, err
	}
	return s.recordIntent(ctx, coordinate, spec, computeLastAppliedHash)
}

func (s Service) recordIntent(ctx context.Context, coordinate Coordinate, spec IntentSpec, hashMode lastAppliedHashMode) (Entry, error) {
	if err := validateIntentSpec(spec); err != nil {
		return Entry{}, err
	}
	existing, found, err := s.load(ctx, coordinate)
	if err != nil {
		return Entry{}, err
	}
	if found {
		return existing, nil
	}

	lastAppliedHash := ""
	if hashMode == computeLastAppliedHash {
		lastAppliedHash, err = coreutils.StableHash(spec.LastApplied)
		if err != nil {
			return Entry{}, fmt.Errorf("%w: last-applied value: %w", ErrInvalidIntent, err)
		}
	}
	entry := Entry{
		Coordinate: coordinate, Phase: PhaseIntent, ExternalID: spec.ExternalID,
		Vendor: coordinate.Vendor, Account: coordinate.Account, Region: spec.Region,
		SecretPath: spec.SecretPath, Generation: spec.Generation, LastAppliedHash: lastAppliedHash,
	}
	if err := s.stampCreated(&entry); err != nil {
		return Entry{}, err
	}
	if err := s.store.Put(ctx, entry); err != nil {
		return Entry{}, err
	}
	return entry, nil
}

// Adopt reactivates only orphaned entries and never resurrects a tombstone.
func (s Service) Adopt(ctx context.Context, coordinate Coordinate) (Entry, error) {
	entry, found, err := s.load(ctx, coordinate)
	if err != nil {
		return Entry{}, err
	}
	if !found {
		return Entry{}, transitionError(coordinate, "adopt", Phase("missing"), ErrMissingEntry)
	}
	switch entry.Phase {
	case PhaseOrphaned:
		entry.Phase = PhaseCreated
		return s.persistTransition(ctx, coordinate, entry, "")
	case PhaseIntent, PhaseCreated, PhaseConfirmed:
		return entry, nil
	default:
		return Entry{}, transitionError(coordinate, "adopt", entry.Phase, ErrInvalidTransition)
	}
}

// Created records intent -> created. The compatibility facade retains the old
// return-unchanged behavior for out-of-order calls; strict services reject them.
func (s Service) Created(ctx context.Context, coordinate Coordinate) (Entry, error) {
	entry, found, err := s.load(ctx, coordinate)
	if err != nil {
		return Entry{}, err
	}
	if !found {
		return Entry{}, transitionError(coordinate, "mark created", Phase("missing"), ErrMissingEntry)
	}
	switch entry.Phase {
	case PhaseIntent:
		entry.Phase = PhaseCreated
		return s.persistTransition(ctx, coordinate, entry, "")
	case PhaseCreated, PhaseConfirmed:
		return entry, nil
	default:
		if s.lenient {
			return entry, nil
		}
		return Entry{}, transitionError(coordinate, "mark created", entry.Phase, ErrInvalidTransition)
	}
}

// Confirm records created -> confirmed. Strict services reject skipped or
// orphaned states; the inherited facade returns them unchanged for compatibility.
func (s Service) Confirm(ctx context.Context, coordinate Coordinate) (Entry, error) {
	entry, found, err := s.load(ctx, coordinate)
	if err != nil {
		return Entry{}, err
	}
	if !found {
		return Entry{}, transitionError(coordinate, "confirm", Phase("missing"), ErrMissingEntry)
	}
	switch entry.Phase {
	case PhaseCreated:
		entry.Phase = PhaseConfirmed
		return s.persistTransition(ctx, coordinate, entry, "")
	case PhaseConfirmed:
		return entry, nil
	default:
		if s.lenient {
			return entry, nil
		}
		return Entry{}, transitionError(coordinate, "confirm", entry.Phase, ErrInvalidTransition)
	}
}

// Orphan marks a present active entry orphaned on CR deletion. Missing and
// already-orphaned entries are idempotent no-ops; tombstones are immutable.
func (s Service) Orphan(ctx context.Context, coordinate Coordinate) error {
	entry, found, err := s.load(ctx, coordinate)
	if err != nil {
		return err
	}
	if !found {
		return nil
	}
	switch entry.Phase {
	case PhaseIntent, PhaseCreated, PhaseConfirmed:
		entry.Phase = PhaseOrphaned
		_, err = s.persistTransition(ctx, coordinate, entry, "orphaned")
		return err
	case PhaseOrphaned:
		return nil
	default:
		return transitionError(coordinate, "orphan", entry.Phase, ErrInvalidTransition)
	}
}

// AdvanceGeneration monotonically advances the generation fence and recomputes
// LastAppliedHash. Equal generations replay without a write; lower generations
// are rejected so a stale actor cannot overwrite newer allocation state.
func (s Service) AdvanceGeneration(ctx context.Context, coordinate Coordinate, generation int64, lastApplied any) (Entry, error) {
	if err := s.requireStrict("advance generation"); err != nil {
		return Entry{}, err
	}
	if generation < 0 {
		return Entry{}, fmt.Errorf("%w: generation must be non-negative", ErrInvalidIntent)
	}
	entry, found, err := s.load(ctx, coordinate)
	if err != nil {
		return Entry{}, err
	}
	if !found {
		return Entry{}, transitionError(coordinate, "advance generation", Phase("missing"), ErrMissingEntry)
	}
	switch entry.Phase {
	case PhaseIntent, PhaseCreated, PhaseConfirmed, PhaseOrphaned:
	default:
		return Entry{}, transitionError(coordinate, "advance generation", entry.Phase, ErrInvalidTransition)
	}
	if generation < entry.Generation {
		return Entry{}, &GenerationError{Coordinate: coordinate, Stored: entry.Generation, Attempted: generation}
	}
	if generation == entry.Generation {
		return entry, nil
	}
	hash, err := coreutils.StableHash(lastApplied)
	if err != nil {
		return Entry{}, fmt.Errorf("%w: last-applied value: %w", ErrInvalidIntent, err)
	}
	entry.Generation = generation
	entry.LastAppliedHash = hash
	return s.persistTransition(ctx, coordinate, entry, "")
}

// Tombstone records a proved spec-removal deletion and the exact 168-hour
// retain intent. It never performs the snapshot or vendor deletion itself.
func (s Service) Tombstone(ctx context.Context, coordinate Coordinate, proof TombstoneProof) (Entry, error) {
	if err := s.requireStrict("tombstone"); err != nil {
		return Entry{}, err
	}
	if !proof.complete {
		return Entry{}, ErrInvalidTombstoneProof
	}
	entry, found, err := s.load(ctx, coordinate)
	if err != nil {
		return Entry{}, err
	}
	if !found {
		return Entry{}, transitionError(coordinate, "tombstone", Phase("missing"), ErrMissingEntry)
	}
	switch entry.Phase {
	case PhaseCreated, PhaseConfirmed, PhaseOrphaned:
	case PhaseTombstoned:
		return entry, nil
	default:
		return Entry{}, transitionError(coordinate, "tombstone", entry.Phase, ErrInvalidTransition)
	}

	entry.Phase = PhaseTombstoned
	prepareForWrite(&entry, coordinate)
	instant, timestamp, err := s.timestamp()
	if err != nil {
		return Entry{}, err
	}
	retainUntil, err := FormatTimestamp(instant.Add(SecretRetainGrace))
	if err != nil {
		return Entry{}, err
	}
	entry.Timestamps.UpdatedAt = timestamp
	entry.Timestamps.TombstonedAt = timestamp
	entry.Timestamps.RetainUntil = retainUntil
	if err := s.store.Put(ctx, entry); err != nil {
		return Entry{}, err
	}
	return entry, nil
}

// Purge physically removes a ledger object only when both the separately wired
// capability and a complete Decommission permit are present.
func (s Service) Purge(ctx context.Context, coordinate Coordinate, permit PurgePermit) error {
	if err := coordinate.Validate(); err != nil {
		return err
	}
	if !permit.complete {
		return ErrInvalidPurgePermit
	}
	if s.purge == nil {
		return ErrPurgeUnavailable
	}
	return s.purge.Purge(ctx, coordinate.Key())
}

func validateIntentSpec(spec IntentSpec) error {
	if strings.TrimSpace(spec.ExternalID) == "" {
		return fmt.Errorf("%w: external ID must be nonblank", ErrInvalidIntent)
	}
	if strings.TrimSpace(spec.SecretPath) == "" {
		return fmt.Errorf("%w: secret path pointer must be nonblank", ErrInvalidIntent)
	}
	if spec.Generation < 0 {
		return fmt.Errorf("%w: generation must be non-negative", ErrInvalidIntent)
	}
	return nil
}

func (s Service) load(ctx context.Context, coordinate Coordinate) (Entry, bool, error) {
	if err := coordinate.Validate(); err != nil {
		return Entry{}, false, err
	}
	if s.store == nil {
		return Entry{}, false, fmt.Errorf("%w: store is required", ErrInvalidService)
	}
	return s.store.Get(ctx, coordinate.Key())
}

func (s Service) requireStrict(operation string) error {
	if s.lenient || s.now == nil {
		return fmt.Errorf("%w: %s", ErrStrictServiceRequired, operation)
	}
	return nil
}

func (s Service) stampCreated(entry *Entry) error {
	if s.now == nil {
		return nil
	}
	_, timestamp, err := s.timestamp()
	if err != nil {
		return err
	}
	entry.Timestamps.CreatedAt = timestamp
	entry.Timestamps.UpdatedAt = timestamp
	return nil
}

func (s Service) persistTransition(ctx context.Context, coordinate Coordinate, entry Entry, phaseTimestamp string) (Entry, error) {
	prepareForWrite(&entry, coordinate)
	_, timestamp, err := s.timestamp()
	if err != nil {
		return Entry{}, err
	}
	if timestamp != "" {
		entry.Timestamps.UpdatedAt = timestamp
		if phaseTimestamp == "orphaned" {
			entry.Timestamps.OrphanedAt = timestamp
		}
	}
	if err := s.store.Put(ctx, entry); err != nil {
		return Entry{}, err
	}
	return entry, nil
}

func prepareForWrite(entry *Entry, coordinate Coordinate) {
	entry.Coordinate = coordinate
	entry.Vendor = coordinate.Vendor
	entry.Account = coordinate.Account
}

func (s Service) timestamp() (time.Time, string, error) {
	if s.now == nil {
		return time.Time{}, "", nil
	}
	instant := s.now().UTC()
	formatted, err := FormatTimestamp(instant)
	if err != nil {
		return time.Time{}, "", err
	}
	return instant, formatted, nil
}

func transitionError(coordinate Coordinate, operation string, from Phase, cause error) error {
	return &TransitionError{Coordinate: coordinate, Operation: operation, From: from, Cause: cause}
}
