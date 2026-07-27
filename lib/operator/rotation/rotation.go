// Package rotation holds the pure, crash-resumable dual-generation credential
// mint state machine every registered-fleet external type rotates through. Two
// concurrent credentials (generation N and N+1) exist during an overlap window so
// consumers roll over with zero downtime, and the AWS two-key limit means there is
// never a spare slot — a rotation that crashes mid-flight resumes the in-flight
// generation, it never restarts.
//
// The walk is:
//
//	MintPlanned(N+1) -> Minted -> Committed -> SmokePassed -> FannedOut ->
//	Confirmed(per-cluster acks) -> OverlapClockStarted(48h from the LAST
//	confirmation) -> Revoked(N) -> ResmokePassed -> GenerationAdvanced.
//
// Fix-3 COMMIT law: a mint is not a mint until the new secret is durably recorded.
// The machine refuses to smoke or fan out before the Committed phase, so an
// unconfirmed vendor key can never be advertised to consumers.
//
// This package is pure domain: it imports no Kubernetes packages and performs no
// vendor, Infisical, or ledger I/O. Those are Phase 3 adapters the caller drives
// FROM this machine. Time is supplied by an injected clock so every transition and
// the 48h overlap deadline are deterministic. Rotation on/off is caller policy;
// Garden realizations and preview forks never enter this machine (they advance a
// generation-fenced allocation through the ledger instead) and are therefore out
// of scope here by construction.
package rotation

import (
	"errors"
	"fmt"
	"slices"
	"strings"
	"time"
)

// OverlapWindow is the fixed dual-credential overlap: the old generation is
// revoked only after exactly 48 hours have elapsed since the LAST required
// confirmation, giving every consumer time to observe the new generation.
const OverlapWindow = 48 * time.Hour

// Stable error categories. Concrete transition, predicate, and input errors
// unwrap to these values so callers can use errors.Is.
var (
	ErrInvalidState        = errors.New("rotation: invalid state")
	ErrInvalidClock        = errors.New("rotation: clock is required")
	ErrInvalidPhase        = errors.New("rotation: invalid phase")
	ErrInvalidGeneration   = errors.New("rotation: invalid generation")
	ErrInvalidTransition   = errors.New("rotation: invalid transition")
	ErrCommitRequired      = errors.New("rotation: durable commit required before smoke or fan-out")
	ErrNoClusters          = errors.New("rotation: at least one confirmation cluster is required")
	ErrInvalidCluster      = errors.New("rotation: invalid cluster")
	ErrDuplicateCluster    = errors.New("rotation: duplicate cluster")
	ErrUnknownCluster      = errors.New("rotation: cluster is not in the fan-out set")
	ErrMissingConfirmation = errors.New("rotation: confirmations incomplete")
	ErrOverlapNotElapsed   = errors.New("rotation: 48h overlap window has not elapsed")
	ErrProtectedActiveKey  = errors.New("rotation: refuses to revoke the protected active key")
)

// Phase is the durable state of a dual-generation rotation.
type Phase string

// The rotation phases, in walk order.
const (
	PhaseMintPlanned         Phase = "MintPlanned"
	PhaseMinted              Phase = "Minted"
	PhaseCommitted           Phase = "Committed"
	PhaseSmokePassed         Phase = "SmokePassed"
	PhaseFannedOut           Phase = "FannedOut"
	PhaseConfirmed           Phase = "Confirmed"
	PhaseOverlapClockStarted Phase = "OverlapClockStarted"
	PhaseRevoked             Phase = "Revoked"
	PhaseResmokePassed       Phase = "ResmokePassed"
	PhaseGenerationAdvanced  Phase = "GenerationAdvanced"
)

// order is the monotonic rank of each phase; it also serves as the set of valid
// phases. A phase absent from this map is invalid.
var order = map[Phase]int{
	PhaseMintPlanned:         0,
	PhaseMinted:              1,
	PhaseCommitted:           2,
	PhaseSmokePassed:         3,
	PhaseFannedOut:           4,
	PhaseConfirmed:           5,
	PhaseOverlapClockStarted: 6,
	PhaseRevoked:             7,
	PhaseResmokePassed:       8,
	PhaseGenerationAdvanced:  9,
}

// Valid reports whether p is a known rotation phase.
func (p Phase) Valid() bool {
	_, ok := order[p]
	return ok
}

// committed reports whether the phase is at or after the durable COMMIT, which is
// the Fix-3 precondition for smoke and fan-out.
func (p Phase) committed() bool {
	return order[p] >= order[PhaseCommitted]
}

// State is the persisted, JSON-serializable progress of one in-flight rotation.
// A constructor consumes it verbatim and continues the in-flight generation; it is
// never silently reset. ActiveGeneration is the generation being replaced (N);
// NextGeneration is the generation being minted (N+1). Timestamps are UTC.
type State struct {
	Phase              Phase     `json:"phase"`
	ActiveGeneration   int64     `json:"activeGeneration"`
	NextGeneration     int64     `json:"nextGeneration"`
	RequiredClusters   []string  `json:"requiredClusters,omitempty"`
	Confirmed          []string  `json:"confirmed,omitempty"`
	LastConfirmationAt time.Time `json:"lastConfirmationAt,omitzero"`
	OverlapDeadline    time.Time `json:"overlapDeadline,omitzero"`
}

// clone returns a deep copy so callers cannot alias the machine's backing slices.
func (s State) clone() State {
	out := s
	out.RequiredClusters = append([]string(nil), s.RequiredClusters...)
	out.Confirmed = append([]string(nil), s.Confirmed...)
	return out
}

// Clock supplies the current instant. It is injected so transitions and the 48h
// overlap deadline are deterministic under test.
type Clock func() time.Time

// Machine is the pure rotation state machine. Construct it with New (resume) or
// Begin (fresh). Transition methods advance the internal state and return the new
// snapshot to persist; on error the internal state is left unchanged.
type Machine struct {
	now   Clock
	state State
}

// New resumes a rotation from persisted state. It validates the state structurally
// and adopts the in-flight phase as-is — it never restarts a partially-complete
// rotation. The clock is mandatory and fails closed when absent.
func New(state State, now Clock) (*Machine, error) {
	if now == nil {
		return nil, ErrInvalidClock
	}
	if !state.Phase.Valid() {
		return nil, fmt.Errorf("%w: %q", ErrInvalidPhase, state.Phase)
	}
	if state.ActiveGeneration < 0 || state.NextGeneration < 0 {
		return nil, fmt.Errorf("%w: generations must be non-negative", ErrInvalidGeneration)
	}
	if err := validateClusters(state.RequiredClusters); err != nil {
		return nil, err
	}
	required := toSet(state.RequiredClusters)
	seen := map[string]struct{}{}
	for _, cluster := range state.Confirmed {
		if strings.TrimSpace(cluster) == "" {
			return nil, fmt.Errorf("%w: confirmed cluster must be nonblank", ErrInvalidCluster)
		}
		if _, ok := required[cluster]; !ok {
			return nil, fmt.Errorf("%w: confirmed cluster %q is not in the fan-out set", ErrUnknownCluster, cluster)
		}
		if _, dup := seen[cluster]; dup {
			return nil, fmt.Errorf("%w: confirmed cluster %q", ErrDuplicateCluster, cluster)
		}
		seen[cluster] = struct{}{}
	}
	return &Machine{now: now, state: state.clone()}, nil
}

// Begin starts a fresh rotation that plans minting generation activeGeneration+1.
// It fails closed on a negative active generation.
func Begin(activeGeneration int64, now Clock) (*Machine, error) {
	if activeGeneration < 0 {
		return nil, fmt.Errorf("%w: active generation must be non-negative", ErrInvalidGeneration)
	}
	return New(State{
		Phase:            PhaseMintPlanned,
		ActiveGeneration: activeGeneration,
		NextGeneration:   activeGeneration + 1,
	}, now)
}

// State returns a copy of the current persisted state.
func (m *Machine) State() State { return m.state.clone() }

// Phase returns the current phase.
func (m *Machine) Phase() Phase { return m.state.Phase }

// Mint records MintPlanned -> Minted: the engine now holds both generation N and
// N+1. The new secret is NOT yet durable, so smoke and fan-out remain refused.
func (m *Machine) Mint() (State, error) {
	return m.advance("mint", PhaseMintPlanned, PhaseMinted)
}

// Commit records Minted -> Committed: the Fix-3 COMMIT. The new secret is now
// durably recorded, so it is legal to smoke it.
func (m *Machine) Commit() (State, error) {
	return m.advance("commit", PhaseMinted, PhaseCommitted)
}

// Smoke records Committed -> SmokePassed. It refuses (ErrCommitRequired) before the
// durable COMMIT so an uncommitted key is never smoked (Fix-3).
func (m *Machine) Smoke() (State, error) {
	if !m.state.Phase.committed() {
		return State{}, &TransitionError{Operation: "smoke", From: m.state.Phase, Cause: ErrCommitRequired}
	}
	return m.advance("smoke", PhaseCommitted, PhaseSmokePassed)
}

// FanOut records SmokePassed -> FannedOut against the required confirmation
// clusters. It refuses (ErrCommitRequired) before the durable COMMIT so an
// uncommitted key is never fanned out to consumers (Fix-3), and requires at least
// one nonblank, duplicate-free cluster.
func (m *Machine) FanOut(clusters []string) (State, error) {
	if !m.state.Phase.committed() {
		return State{}, &TransitionError{Operation: "fan out", From: m.state.Phase, Cause: ErrCommitRequired}
	}
	if m.state.Phase != PhaseSmokePassed {
		return State{}, &TransitionError{Operation: "fan out", From: m.state.Phase, Cause: ErrInvalidTransition}
	}
	if len(clusters) == 0 {
		return State{}, ErrNoClusters
	}
	if err := validateClusters(clusters); err != nil {
		return State{}, err
	}
	m.state.Phase = PhaseFannedOut
	m.state.RequiredClusters = append([]string(nil), clusters...)
	m.state.Confirmed = nil
	return m.state.clone(), nil
}

// Confirm records a per-cluster acknowledgement of the new generation while in the
// FannedOut phase. An unknown cluster fails closed; a repeated confirmation is an
// idempotent no-op. When the last required cluster confirms, the phase advances to
// Confirmed and the 48h overlap clock is anchored at that instant.
func (m *Machine) Confirm(cluster string) (State, error) {
	if m.state.Phase != PhaseFannedOut {
		return State{}, &TransitionError{Operation: "confirm", From: m.state.Phase, Cause: ErrInvalidTransition}
	}
	if strings.TrimSpace(cluster) == "" {
		return State{}, fmt.Errorf("%w: cluster must be nonblank", ErrInvalidCluster)
	}
	required := toSet(m.state.RequiredClusters)
	if _, ok := required[cluster]; !ok {
		return State{}, fmt.Errorf("%w: %q", ErrUnknownCluster, cluster)
	}
	if slices.Contains(m.state.Confirmed, cluster) {
		return m.state.clone(), nil
	}
	m.state.Confirmed = append(m.state.Confirmed, cluster)
	if len(m.state.Confirmed) == len(m.state.RequiredClusters) {
		m.state.Phase = PhaseConfirmed
		m.state.LastConfirmationAt = m.now().UTC()
	}
	return m.state.clone(), nil
}

// StartOverlapClock records Confirmed -> OverlapClockStarted and pins the overlap
// deadline at exactly 48 hours after the last required confirmation.
func (m *Machine) StartOverlapClock() (State, error) {
	if m.state.Phase != PhaseConfirmed {
		return State{}, &TransitionError{Operation: "start overlap clock", From: m.state.Phase, Cause: ErrInvalidTransition}
	}
	if m.state.LastConfirmationAt.IsZero() {
		return State{}, fmt.Errorf("%w: last confirmation instant is unset", ErrInvalidState)
	}
	m.state.Phase = PhaseOverlapClockStarted
	m.state.OverlapDeadline = m.state.LastConfirmationAt.Add(OverlapWindow)
	return m.state.clone(), nil
}

// CanRevoke reports whether revoking generation target is currently legal, failing
// closed with a specific cause otherwise. It is independent of how the state was
// reached, so a resumed or corrupt state is judged on its own merits: the phase
// must be OverlapClockStarted, every required cluster must have confirmed, the 48h
// overlap window must have elapsed, and target must be the old generation — never
// the protected active (N+1) key.
func (m *Machine) CanRevoke(target int64) error {
	if m.state.Phase != PhaseOverlapClockStarted {
		return &TransitionError{Operation: "revoke", From: m.state.Phase, Cause: ErrInvalidTransition}
	}
	if len(m.state.RequiredClusters) == 0 || len(m.state.Confirmed) < len(m.state.RequiredClusters) {
		return ErrMissingConfirmation
	}
	if m.state.OverlapDeadline.IsZero() {
		return fmt.Errorf("%w: overlap deadline is unset", ErrInvalidState)
	}
	if m.now().UTC().Before(m.state.OverlapDeadline) {
		return ErrOverlapNotElapsed
	}
	if target != m.state.ActiveGeneration {
		return fmt.Errorf("%w: generation %d is protected; only the old generation %d may be revoked", ErrProtectedActiveKey, target, m.state.ActiveGeneration)
	}
	return nil
}

// Revoke records OverlapClockStarted -> Revoked for the old generation target. It
// applies the CanRevoke fail-closed predicate first and leaves the state unchanged
// on refusal.
func (m *Machine) Revoke(target int64) (State, error) {
	if err := m.CanRevoke(target); err != nil {
		return State{}, err
	}
	m.state.Phase = PhaseRevoked
	return m.state.clone(), nil
}

// Resmoke records Revoked -> ResmokePassed, proving the surviving generation still
// works after the old one is gone.
func (m *Machine) Resmoke() (State, error) {
	return m.advance("resmoke", PhaseRevoked, PhaseResmokePassed)
}

// AdvanceGeneration records ResmokePassed -> GenerationAdvanced, the terminal
// state. The minted generation N+1 becomes the new active generation.
func (m *Machine) AdvanceGeneration() (State, error) {
	if m.state.Phase != PhaseResmokePassed {
		return State{}, &TransitionError{Operation: "advance generation", From: m.state.Phase, Cause: ErrInvalidTransition}
	}
	m.state.Phase = PhaseGenerationAdvanced
	m.state.ActiveGeneration = m.state.NextGeneration
	return m.state.clone(), nil
}

// advance performs a strict single-step transition from -> to, rejecting any other
// source phase with ErrInvalidTransition.
func (m *Machine) advance(operation string, from, to Phase) (State, error) {
	if m.state.Phase != from {
		return State{}, &TransitionError{Operation: operation, From: m.state.Phase, Cause: ErrInvalidTransition}
	}
	m.state.Phase = to
	return m.state.clone(), nil
}

// TransitionError identifies a rejected transition, its operation, and the source
// phase. Cause is ErrInvalidTransition or ErrCommitRequired.
type TransitionError struct {
	Operation string
	From      Phase
	Cause     error
}

// Error implements error.
func (e *TransitionError) Error() string {
	return fmt.Sprintf("rotation: cannot %s from phase %q: %v", e.Operation, e.From, e.Cause)
}

// Unwrap exposes the stable cause category.
func (e *TransitionError) Unwrap() error { return e.Cause }

// VendorKey identifies a credential key observed at the vendor. Name is the
// ledger-assigned name when the key was durably recorded, and empty for a key that
// was minted but never committed.
type VendorKey struct {
	ID   string
	Name string
}

// CommittedLedger is the durable ledger view the orphan rule reconciles vendor
// state against: the set of ledger-named keys carrying a durable COMMIT, plus the
// single active key, which is always protected even if a bug dropped it from Names.
type CommittedLedger struct {
	Names     []string
	ActiveKey string
}

// OrphanKey is a vendor key with no durable COMMIT entry: it must be deleted and
// re-minted so the two-key limit is not consumed by a half-done mint.
type OrphanKey struct {
	Key    VendorKey
	Reason string
}

// Reconcile classifies vendor keys against the committed ledger on restart (the
// Fix-3 orphan rule). A key whose Name carries a durable COMMIT — or that is the
// active ledger-named key — is protected and never returned. Every other key is an
// orphan: minted with no COMMIT, so it is deleted and re-minted. Classification is
// pure and preserves input order; execution is a Phase 3 adapter concern.
func Reconcile(vendorKeys []VendorKey, ledger CommittedLedger) []OrphanKey {
	committed := toSet(ledger.Names)
	active := strings.TrimSpace(ledger.ActiveKey)
	var orphans []OrphanKey
	for _, key := range vendorKeys {
		name := strings.TrimSpace(key.Name)
		if active != "" && name == active {
			continue
		}
		if _, ok := committed[name]; ok && name != "" {
			continue
		}
		orphans = append(orphans, OrphanKey{Key: key, Reason: "no durable COMMIT entry"})
	}
	return orphans
}

// validateClusters rejects a nil/empty set, blank names, and duplicates.
func validateClusters(clusters []string) error {
	if len(clusters) == 0 {
		return nil
	}
	seen := make(map[string]struct{}, len(clusters))
	for _, cluster := range clusters {
		if strings.TrimSpace(cluster) == "" {
			return fmt.Errorf("%w: cluster must be nonblank", ErrInvalidCluster)
		}
		if _, ok := seen[cluster]; ok {
			return fmt.Errorf("%w: %q", ErrDuplicateCluster, cluster)
		}
		seen[cluster] = struct{}{}
	}
	return nil
}

// toSet builds a membership set over the entries of values.
func toSet(values []string) map[string]struct{} {
	set := make(map[string]struct{}, len(values))
	for _, value := range values {
		set[value] = struct{}{}
	}
	return set
}
