package authengine

import (
	"slices"

	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
)

// ScopeChecker reads coarse role and scope claims off a principal.
//
// It is a seam so an application whose IdP tenant emits roles under a different
// claim, or which needs a hierarchical role read, can supply its own reader
// without reimplementing the guard.
type ScopeChecker interface {
	// Scope returns the values the principal carries under the named claim field.
	Scope(principal Principal, field string) []string
	// HasAny reports whether the principal carries at least one of values.
	HasAny(principal Principal, field string, values []string) bool
	// HasAll reports whether the principal carries every one of values.
	HasAll(principal Principal, field string, values []string) bool
}

// ClaimScopeChecker is the default [ScopeChecker]: it reads the mapped roles for
// the roles claim, the mapped scopes for the scope claim, and any other field
// straight off the validated claim set.
type ClaimScopeChecker struct{}

// Scope returns the principal's values for the named claim field.
func (ClaimScopeChecker) Scope(principal Principal, field string) []string {
	switch field {
	case ClaimRoles:
		return principal.Roles
	case ClaimScope:
		return principal.Scopes
	default:
		values, _ := principal.Claims.List(field)
		return values
	}
}

// HasAny reports whether the principal carries at least one of values. An empty
// requirement never passes: "any of nothing" is a wiring mistake, and treating it
// as satisfied would silently open the endpoint.
func (c ClaimScopeChecker) HasAny(principal Principal, field string, values []string) bool {
	granted := c.Scope(principal, field)
	for _, required := range values {
		if slices.Contains(granted, required) {
			return true
		}
	}
	return false
}

// HasAll reports whether the principal carries every one of values. An empty
// requirement never passes, for the same reason as [ClaimScopeChecker.HasAny].
func (c ClaimScopeChecker) HasAll(principal Principal, field string, values []string) bool {
	if len(values) == 0 {
		return false
	}
	granted := c.Scope(principal, field)
	for _, required := range values {
		if !slices.Contains(granted, required) {
			return false
		}
	}
	return true
}

// GuardOptions configures a [Guard].
type GuardOptions struct {
	// Problems mints the problem-typed denials.
	Problems *Problems
	// Checker reads role and scope claims. Nil uses [ClaimScopeChecker].
	Checker ScopeChecker
	// Logs receives one informational record per denial. Nil disables logging.
	Logs interfaces.LoggerSink
	// Clock timestamps denial records. Nil disables logging.
	Clock interfaces.System
}

// Guard enforces the family nullable-userId ownership pattern.
//
// The pattern composes three things that already exist — the token `sub`, coarse
// role claims, and the data layer's WHERE clause — so one endpoint serves both
// the resource owner and admin callers with no branching in the service layer:
//
//	owner    → passes its OWN userId → sub matches → data layer filters to that owner
//	admin    → OMITS userId (nil)    → sub half fails, role half passes → no filter
//	attacker → passes SOMEBODY ELSE'S userId → both halves fail → 403
//
// The load-bearing detail is that a nil target NEVER passes the sub half. That is
// what makes omitting the userId an admin-only move, and it is why the data
// layer's "no userId means no filter" rule is safe: the guard already proved that
// nil implies role-holder.
//
// This is not a fine-grained-authorization system and no policy engine is coming.
// It is also transport-free: the Go family has no server-engine analogue, so this
// type returns decisions and never touches an HTTP request. A consumer with an
// HTTP surface calls it as the FIRST step of its handler, before the service call.
type Guard struct {
	problems *Problems
	checker  ScopeChecker
	logs     interfaces.LoggerSink
	clock    interfaces.System
}

// NewGuard creates a guard. Logging is optional; the denial itself is always
// problem-typed, so a consumer that does not want auth logs simply omits the sink.
func NewGuard(options GuardOptions) (Guard, error) {
	if options.Problems == nil {
		return Guard{}, errUnconfigured("guard")
	}
	checker := options.Checker
	if checker == nil {
		checker = ClaimScopeChecker{}
	}
	return Guard{
		problems: options.Problems,
		checker:  checker,
		logs:     options.Logs,
		clock:    options.Clock,
	}, nil
}

// Sub passes only when target is non-nil and equals the principal's subject:
// owner-only, with no admin override.
func (g Guard) Sub(principal Principal, target *string) error {
	if guardOwns(principal, target) {
		return nil
	}
	return g.deny(principal, target, "", nil)
}

// SubOrAny passes when the principal owns target OR carries any of values under
// field. This is the everyday owned-resource guard: admin and system callers pass
// nil as target and clear the role half.
func (g Guard) SubOrAny(principal Principal, target *string, field string, values ...string) error {
	if guardOwns(principal, target) || g.checker.HasAny(principal, field, values) {
		return nil
	}
	return g.deny(principal, target, field, values)
}

// SubOrAll passes when the principal owns target OR carries every one of values
// under field. Stricter write paths use this so a single elevated role is not
// enough on its own.
func (g Guard) SubOrAll(principal Principal, target *string, field string, values ...string) error {
	if guardOwns(principal, target) || g.checker.HasAll(principal, field, values) {
		return nil
	}
	return g.deny(principal, target, field, values)
}

// Registered passes when the principal carries the per-backend registration
// claim for backend.
//
// This is the family's Registered policy wired as a REAL default rather than the
// declared-but-unused policy the seed stack shipped: an authenticated caller that
// never completed OnboardSync should be told so, not left to collide with
// domain-level not-founds and foreign-key failures deeper in the request.
func (g Guard) Registered(principal Principal, backend string) error {
	if principal.Registered(backend) {
		return nil
	}
	return g.problems.Raise(ProblemRegistrationMissing,
		"the caller has not completed onboarding against this backend",
		map[string]any{
			"subject": principal.Subject,
			"backend": backend,
			"claim":   RegistrationClaim(backend),
		})
}

// owns reports whether target names the principal itself. A nil target is never
// ownership — see the [Guard] contract.
func guardOwns(principal Principal, target *string) bool {
	return target != nil && principal.Subject == *target && principal.Subject != ""
}

// deny builds the problem-typed denial and records which half failed, so an
// operator reading logs can tell a mis-scoped client from a genuine intrusion
// attempt.
func (g Guard) deny(principal Principal, target *string, field string, values []string) error {
	data := map[string]any{
		"subject":  principal.Subject,
		"target":   textOrNil(target),
		"ownsSub":  false,
		"field":    field,
		"required": values,
		"granted":  g.checker.Scope(principal, field),
	}
	g.log(data)
	return g.problems.Raise(ProblemOwnershipDenied,
		"the caller neither owns the target resource nor holds a required role", data)
}

// log emits one informational denial record when a sink and clock are bound.
func (g Guard) log(data map[string]any) {
	if g.logs == nil || g.clock == nil {
		return
	}
	now, err := g.clock.NowUTC()
	if err != nil {
		return
	}
	_ = g.logs.Emit(interfaces.NewLogRecord(now, interfaces.LogLevelInfo,
		"auth failed", data, nil, nil))
}

// textOrNil renders an optional target for a log or problem payload without
// collapsing absent into empty.
func textOrNil(target *string) any {
	if target == nil {
		return nil
	}
	return *target
}
