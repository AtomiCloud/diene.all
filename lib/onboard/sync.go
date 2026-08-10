package onboard

import (
	"context"

	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
)

// Registration is the payload a backend registers a caller with.
type Registration struct {
	// Subject is the identity being registered.
	Subject string
	// Username is the caller's username claim.
	Username string
	// Email is the caller's email claim.
	Email string
	// AccessToken is the raw access token the backend re-validates as data.
	AccessToken string
	// IDToken is the raw ID token the backend re-validates as data.
	IDToken string
}

// Backend is one registered backend's onboarding surface.
//
// Create must be IDEMPOTENT — create-or-ok. The seed stack's create-only endpoint
// returned a conflict on a repeat call and the claim write-back did not re-run,
// which left a client permanently stuck between "no claim" and "already exists".
// An implementation that cannot be idempotent server-side must at minimum report a
// conflict as success.
type Backend interface {
	// Name returns the backend's resource-tree name.
	Name() string
	// Exists reports whether the backend already holds a user row for the caller.
	// It is the create-time RACE handler, not a second onboarding detector: it is
	// consulted only after the registration claim was found ABSENT.
	Exists(ctx context.Context, token authengine.AccessToken) (bool, error)
	// Create registers the caller, treating an already-registered caller as
	// success.
	Create(ctx context.Context, token authengine.AccessToken, registration Registration) error
}

// Configurable is an optional [Backend] capability for a backend whose onboarding
// has a SECOND, app-specific step.
//
// Registration is the portable half: a user row plus the `<platform>_<service>`
// claim. Some backends additionally need a user-facing configuration step, and that
// step cannot be completed by a library — it needs real UX. A backend that reports
// itself unconfigured therefore rests in [PhaseNeedsOnboarding] rather than in
// [PhaseReady], which is the signal a consumer's gate routes to its own onboarding
// page. Backends without a second step simply do not implement this.
type Configurable interface {
	// Configured reports whether the caller has completed the backend's
	// app-specific onboarding step.
	Configured(ctx context.Context, token authengine.AccessToken) (bool, error)
}

// ClaimWriter writes the per-backend registration claim back to the identity
// provider.
type ClaimWriter interface {
	// SetClaim writes value under name on the identity provider user subject.
	SetClaim(ctx context.Context, subject string, name string, value any) error
}

// TokenRefresher forces a fresh token set so a just-written claim becomes visible.
//
// Claim propagation is treated as synchronous: the client refreshes and re-checks
// immediately, and a claim that still does not appear is a real failure rather than
// something to poll for.
type TokenRefresher interface {
	// Refresh returns a principal built from a newly fetched token set.
	Refresh(ctx context.Context, subject string) (authengine.Principal, error)
}

// SyncOptions configures a [Sync].
type SyncOptions struct {
	// Backends are the registered backends, keyed by name in the returned state.
	Backends []Backend
	// Claims writes registration claims back to the identity provider.
	Claims ClaimWriter
	// Refresher forces a token refresh after a claim write-back.
	Refresher TokenRefresher
	// Tokens resolves the per-resource access token for each backend.
	Tokens authengine.Retriever
	// Problems mints problem-typed failures.
	Problems *authengine.Problems
}

// Sync is OnboardSync: it brings every registered backend to a known phase.
//
// The order of operations is the contract, and each step exists because skipping
// it breaks a real case:
//
//  1. Inspect the backend's registration claim. Present ⇒ ready, no API call.
//  2. Absent ⇒ resolve the backend's per-resource token and ask whether a row
//     already exists — this handles the concurrent-first-sign-in race only.
//  3. No row ⇒ create it (idempotently).
//  4. Write the registration claim back to the identity provider.
//  5. Force a token refresh and RE-VERIFY the claim. A claim that still does not
//     appear is a stalled onboarding, not a success.
//
// A stale claim is deliberately NOT handled here: it takes the normal 401/404 path
// on the next real request. Treating a backend GET as a second onboarding detector
// is what made the seed mobile client distrust its own claims.
type Sync struct {
	backends  []Backend
	claims    ClaimWriter
	refresher TokenRefresher
	tokens    authengine.Retriever
	problems  *authengine.Problems
}

// NewSync creates an onboarding gate, rejecting a configuration missing any of its
// seams.
func NewSync(options SyncOptions) (Sync, error) {
	if options.Problems == nil {
		return Sync{}, errUnconfigured()
	}
	if len(options.Backends) == 0 {
		return Sync{}, ErrNoBackends
	}
	if options.Claims == nil {
		return Sync{}, options.Problems.Raise(authengine.ProblemConfigInvalid,
			"a claim writer is required so registration is recorded on the identity provider", nil)
	}
	if options.Refresher == nil {
		return Sync{}, options.Problems.Raise(authengine.ProblemConfigInvalid,
			"a token refresher is required so a written claim can be re-verified", nil)
	}
	if options.Tokens == nil {
		return Sync{}, options.Problems.Raise(authengine.ProblemConfigInvalid,
			"a token retriever is required so each backend is called with its own token", nil)
	}
	return Sync{
		backends:  options.Backends,
		claims:    options.Claims,
		refresher: options.Refresher,
		tokens:    options.Tokens,
		problems:  options.Problems,
	}, nil
}

// Run brings every registered backend to a phase and returns the per-backend
// state.
//
// One backend failing never aborts the others: each gets its own [State], because a
// consumer whose secondary backend is down should still be able to use its primary
// one. The returned error is non-nil only when the round could not start at all.
func (s Sync) Run(ctx context.Context, principal authengine.Principal) (map[string]State, error) {
	if principal.Subject == "" {
		return nil, s.problems.Raise(authengine.ProblemTokenClaimMissing,
			"onboarding requires an authenticated subject",
			map[string]any{"claim": authengine.ClaimSubject})
	}
	states := make(map[string]State, len(s.backends))
	for _, backend := range s.backends {
		states[backend.Name()] = s.reconcile(ctx, principal, backend)
	}
	return states, nil
}

// reconcile brings one backend to a phase.
func (s Sync) reconcile(ctx context.Context, principal authengine.Principal, backend Backend) State {
	name := backend.Name()
	state := State{Backend: name, Phase: PhaseBootstrapping}
	if principal.Registered(name) {
		return s.settle(ctx, state, backend)
	}

	token, err := s.tokens.Token(ctx, name)
	if err != nil {
		return failed(state, err)
	}
	exists, err := backend.Exists(ctx, token)
	if err != nil {
		return failed(state, err)
	}
	if !exists {
		if created := backend.Create(ctx, token, buildRegistration(principal, token)); created != nil {
			return failed(state, created)
		}
		state.Created = true
	}

	claim := authengine.RegistrationClaim(name)
	if written := s.claims.SetClaim(ctx, principal.Subject, claim, "true"); written != nil {
		return failed(state, s.problems.RaiseFrom(authengine.ProblemProviderUnavailable, written,
			"the registration claim could not be written back",
			map[string]any{"backend": name, "claim": claim}))
	}
	state.ClaimWritten = true

	refreshed, err := s.refresher.Refresh(ctx, principal.Subject)
	if err != nil {
		return failed(state, err)
	}
	if !refreshed.Registered(name) {
		return failed(state, s.problems.Raise(authengine.ProblemOnboardingStalled,
			"the registration claim did not appear on a refreshed token",
			map[string]any{"backend": name, "claim": claim}))
	}
	return s.settle(ctx, state, backend)
}

// settle decides between ready and needs-onboarding for a REGISTERED backend: the
// portable half is done, and only a backend with its own app-specific step can hold
// the caller back from here.
func (s Sync) settle(ctx context.Context, state State, backend Backend) State {
	configurable, staged := backend.(Configurable)
	if !staged {
		state.Phase = PhaseReady
		return state
	}
	token, err := s.tokens.Token(ctx, state.Backend)
	if err != nil {
		return failed(state, err)
	}
	configured, err := configurable.Configured(ctx, token)
	if err != nil {
		return failed(state, err)
	}
	if !configured {
		state.Phase = PhaseNeedsOnboarding
		return state
	}
	state.Phase = PhaseReady
	return state
}

// registration builds the payload a backend registers the caller with. The raw
// tokens travel as data so the backend can re-validate them itself rather than
// trusting this client's word about who is being onboarded.
func buildRegistration(principal authengine.Principal, token authengine.AccessToken) Registration {
	registration := Registration{Subject: principal.Subject, AccessToken: token.Value}
	if principal.Username != nil {
		registration.Username = *principal.Username
	}
	if principal.Email != nil {
		registration.Email = *principal.Email
	}
	if raw, found := principal.Claims.Text(RawIDTokenClaim); found {
		registration.IDToken = raw
	}
	return registration
}

// RawIDTokenClaim is the pseudo-claim a consumer may stash its raw ID token under
// so [Sync] can forward it to a backend's create endpoint.
//
// It is a consumer-side convention rather than an IdP claim: the ID token is not
// recoverable from the access token's claims, and threading it through every
// signature would push a detail only the create path needs into every caller.
const RawIDTokenClaim = "atomi_raw_id_token" //nolint:gosec // a claim NAME, not a credential

// failed marks a backend's state as errored while keeping whatever progress the
// round already made, so a caller can tell "created but claim never appeared" from
// "never got off the ground".
func failed(state State, err error) State {
	state.Phase = PhaseError
	state.Err = err
	return state
}
