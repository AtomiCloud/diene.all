package onboard

import (
	"context"
	"errors"
	"slices"
	"time"

	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
)

// Landscape is one entry of the selector document.
//
// Note what it does NOT carry: no addresses and no issuer. The selector document
// is names and metadata only, which is what keeps auth configuration baked at
// build time by construction — a document that carried an issuer would be a
// runtime input to token validation.
type Landscape struct {
	// Name is the landscape identifier the home claim stores.
	Name string `json:"name"`
	// Display is the human-readable label a picker shows.
	Display string `json:"display"`
	// Region is the coarse geographic region.
	Region string `json:"region"`
	// Healthy reports whether the landscape is currently accepting traffic.
	Healthy bool `json:"healthy"`
}

// Pinger measures a landscape's round-trip latency.
//
// The ping URL is derived by CONVENTION from the landscape name rather than read
// from the selector document, for the same reason the document carries no
// addresses: a document that could point a client at an arbitrary host would be a
// redirection primitive.
type Pinger interface {
	// Ping returns the observed latency to landscape.
	Ping(ctx context.Context, landscape Landscape) (time.Duration, error)
}

// SelectorOptions configures a [Selector].
type SelectorOptions struct {
	// Pinger measures candidate latency.
	Pinger Pinger
	// Problems mints problem-typed failures.
	Problems *authengine.Problems
}

// Selector resolves a caller's home landscape.
//
// It runs as the pre-onboarding phase, BEFORE any backend phase machine, and only
// on sign-up: a returning caller already carries the home-landscape claim and
// routes straight to its home region with no extra step. That ordering is what
// keeps federation free of new machinery — once the home landscape is known, its
// backends onboard through the ordinary per-backend contract.
type Selector struct {
	pinger   Pinger
	problems *authengine.Problems
}

// NewSelector creates a selector, rejecting a configuration missing any of its
// seams.
func NewSelector(options SelectorOptions) (Selector, error) {
	if options.Problems == nil {
		return Selector{}, errUnconfigured()
	}
	if options.Pinger == nil {
		return Selector{}, options.Problems.Raise(authengine.ProblemConfigInvalid,
			"a pinger is required to pick a home landscape by latency", nil)
	}
	return Selector{pinger: options.Pinger, problems: options.Problems}, nil
}

// Home returns the caller's home landscape from its claim when present, and
// otherwise picks one by pinging the candidates.
//
// The claim is checked on EVERY sign-in and sign-up, not only the first: a claim
// that disappears — a re-created user, a migrated tenant — must send the caller
// back through the picker rather than leaving it pointed at nothing.
func (s Selector) Home(
	ctx context.Context,
	principal authengine.Principal,
	candidates []Landscape,
) (Landscape, error) {
	if principal.HomeLandscape != nil {
		if declared, found := find(candidates, *principal.HomeLandscape); found {
			return declared, nil
		}
		return Landscape{Name: *principal.HomeLandscape, Healthy: true}, nil
	}
	return s.Pick(ctx, candidates)
}

// Pick chooses the healthy candidate with the lowest observed latency.
//
// A candidate that fails to answer is skipped rather than failing the round: an
// unreachable region is exactly the one a client should not call home. Only when no
// healthy candidate answers at all does this fail, because guessing a home region
// is worse than telling the caller to retry.
func (s Selector) Pick(ctx context.Context, candidates []Landscape) (Landscape, error) {
	var (
		chosen  Landscape
		best    time.Duration
		reached bool
	)
	for _, candidate := range candidates {
		if !candidate.Healthy {
			continue
		}
		latency, err := s.pinger.Ping(ctx, candidate)
		if err != nil {
			continue
		}
		if !reached || latency < best {
			chosen, best, reached = candidate, latency, true
		}
	}
	if !reached {
		return Landscape{}, s.problems.Raise(authengine.ProblemHomeLandscapeUnresolved,
			"no healthy landscape answered the pre-onboarding ping",
			map[string]any{"candidates": names(candidates)})
	}
	return chosen, nil
}

// Claim writes the resolved home landscape back to the identity provider through
// the same custom-data mechanism the registration claims use.
//
// The claim is delivered onto issued tokens by a provider JWT customizer that the
// identity operator owns declaratively; application code only ever reads the
// resulting claim, and this is the one place it writes one.
func (s Selector) Claim(
	ctx context.Context,
	claims ClaimWriter,
	subject string,
	landscape Landscape,
) error {
	if claims == nil {
		return s.problems.Raise(authengine.ProblemConfigInvalid,
			"a claim writer is required to record the home landscape", nil)
	}
	if err := claims.SetClaim(ctx, subject, authengine.ClaimHomeLandscape, landscape.Name); err != nil {
		return s.problems.RaiseFrom(authengine.ProblemProviderUnavailable, err,
			"the home-landscape claim could not be written back",
			map[string]any{"landscape": landscape.Name})
	}
	return nil
}

// find returns the candidate declared under name.
func find(candidates []Landscape, name string) (Landscape, bool) {
	index := slices.IndexFunc(candidates, func(candidate Landscape) bool {
		return candidate.Name == name
	})
	if index < 0 {
		return Landscape{}, false
	}
	return candidates[index], true
}

// names renders the candidate names for a failure payload.
func names(candidates []Landscape) []string {
	rendered := make([]string, 0, len(candidates))
	for _, candidate := range candidates {
		rendered = append(rendered, candidate.Name)
	}
	return rendered
}

// errUnconfigured reports a constructor called without the problem factory every
// other failure is expressed through. It is a plain error by necessity: there is no
// factory available to raise a problem-typed one.
func errUnconfigured() error {
	return errors.New("auth-engine onboarding requires a problem factory")
}
