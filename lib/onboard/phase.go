package onboard

import "errors"

// Phase is one backend's onboarding state.
type Phase string

// The onboarding phases. Every registered backend carries its own phase; the
// pre-onboarding phase is the one exception, because no backend has been chosen
// yet when it runs.
const (
	// PhasePreOnboarding means no home landscape has been resolved yet, so no
	// backend has been selected. It is NOT a per-backend state.
	PhasePreOnboarding Phase = "pre-onboarding"
	// PhaseBootstrapping means the backend's claim is being inspected.
	PhaseBootstrapping Phase = "bootstrapping"
	// PhaseNeedsOnboarding means the backend has no user row for this subject and
	// the consumer must complete its own onboarding step.
	PhaseNeedsOnboarding Phase = "needs-onboarding"
	// PhaseReady means the backend is registered and normal bearer traffic may
	// begin.
	PhaseReady Phase = "ready"
	// PhaseError means the round failed for this backend. Other backends are
	// unaffected.
	PhaseError Phase = "error"
)

// State is one backend's outcome from an onboarding round.
type State struct {
	// Backend is the resource-tree name of the backend.
	Backend string
	// Phase is the backend's resulting phase.
	Phase Phase
	// Created reports whether this round created the backend's user row.
	Created bool
	// ClaimWritten reports whether this round wrote the registration claim back
	// to the identity provider.
	ClaimWritten bool
	// Err is the failure that put the backend in [PhaseError], nil otherwise.
	Err error
}

// Ready reports whether the backend finished the round registered.
func (s State) Ready() bool {
	return s.Phase == PhaseReady
}

// ErrNoBackends reports an onboarding round asked to run against nothing. It is a
// plain error because it is a programming mistake in the caller rather than a
// runtime auth failure.
var ErrNoBackends = errors.New("auth-engine onboarding requires at least one backend")
