package authengine_test

import (
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
	"github.com/AtomiCloud/diene.go-auth-engine/testhelper"
	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
	mocks "github.com/AtomiCloud/diene.go-interfaces/testhelper"
)

// owner is the principal that owns "user-1" and holds no roles.
func owner() authengine.Principal {
	return authengine.NewClaimMapper().Map(authengine.Claims{
		authengine.ClaimSubject: "user-1",
	})
}

// admin is the principal that owns "user-9" but holds the admin and tin roles.
func admin() authengine.Principal {
	return authengine.NewClaimMapper().Map(authengine.Claims{
		authengine.ClaimSubject: "user-9",
		authengine.ClaimRoles:   []any{"admin", "tin"},
		authengine.ClaimScope:   "read:booking",
	})
}

// newGuard builds an ownership guard over the sample problem factory.
func newGuard(t *testing.T) authengine.Guard {
	t.Helper()

	guard, err := authengine.NewGuard(authengine.GuardOptions{Problems: newProblems(t)})
	requireNoError(t, err)
	return guard
}

func TestNewGuardRequiresAProblemFactory(t *testing.T) {
	t.Parallel()

	if _, err := authengine.NewGuard(authengine.GuardOptions{}); err == nil {
		t.Fatal("expected a guard without a problem factory to be rejected")
	}
}

func TestSubIsOwnerOnly(t *testing.T) {
	t.Parallel()

	guard := newGuard(t)

	requireNoError(t, guard.Sub(owner(), new("user-1")))

	// An attacker naming somebody else is denied.
	requireProblem(t, guard.Sub(owner(), new("user-2")), authengine.ProblemOwnershipDenied)
	// A nil target NEVER passes the sub half — this is the load-bearing rule.
	requireProblem(t, guard.Sub(owner(), nil), authengine.ProblemOwnershipDenied)
	// An admin gets no override from Sub: that is what distinguishes it from SubOrAny.
	requireProblem(t, guard.Sub(admin(), nil), authengine.ProblemOwnershipDenied)
}

func TestSubOrAnyServesOwnerAndAdminFromOneEndpoint(t *testing.T) {
	t.Parallel()

	guard := newGuard(t)

	// Owner flow: passes its own userId, sub matches.
	requireNoError(t, guard.SubOrAny(owner(), new("user-1"), authengine.ClaimRoles, "admin", "tin"))
	// Admin flow: OMITS the userId, role half passes, nil flows down unchanged.
	requireNoError(t, guard.SubOrAny(admin(), nil, authengine.ClaimRoles, "admin"))
	// Attacker flow: names somebody else and holds no role.
	requireProblem(t,
		guard.SubOrAny(owner(), new("user-2"), authengine.ClaimRoles, "admin"),
		authengine.ProblemOwnershipDenied)
	// Omitting the userId WITHOUT a role is also denied.
	requireProblem(t,
		guard.SubOrAny(owner(), nil, authengine.ClaimRoles, "admin"),
		authengine.ProblemOwnershipDenied)
}

func TestSubOrAllRequiresEveryListedRole(t *testing.T) {
	t.Parallel()

	guard := newGuard(t)

	requireNoError(t, guard.SubOrAll(admin(), nil, authengine.ClaimRoles, "admin", "tin"))
	// Holding one of the two is not enough on a stricter write path.
	requireProblem(t,
		guard.SubOrAll(admin(), nil, authengine.ClaimRoles, "admin", "field"),
		authengine.ProblemOwnershipDenied)
	// Ownership still passes regardless of the role requirement.
	requireNoError(t, guard.SubOrAll(owner(), new("user-1"), authengine.ClaimRoles, "admin", "field"))
}

func TestGuardRefusesAnEmptyRoleRequirement(t *testing.T) {
	t.Parallel()

	guard := newGuard(t)

	// "any of nothing" and "all of nothing" must both fail closed: an endpoint that
	// forgot to list its roles must not become public.
	requireProblem(t,
		guard.SubOrAny(admin(), nil, authengine.ClaimRoles),
		authengine.ProblemOwnershipDenied)
	requireProblem(t,
		guard.SubOrAll(admin(), nil, authengine.ClaimRoles),
		authengine.ProblemOwnershipDenied)
}

func TestGuardRefusesAnAnonymousPrincipalNamingTheEmptyString(t *testing.T) {
	t.Parallel()

	// A principal with no subject must not "own" the empty userId — otherwise an
	// unauthenticated caller would satisfy the sub half by passing "".
	requireProblem(t,
		newGuard(t).Sub(authengine.Principal{}, new("")),
		authengine.ProblemOwnershipDenied)
}

func TestDenialPayloadNamesBothHalves(t *testing.T) {
	t.Parallel()

	envelope := requireProblem(t,
		newGuard(t).SubOrAny(owner(), new("user-2"), authengine.ClaimRoles, "admin"),
		authengine.ProblemOwnershipDenied)

	if envelope.Status != 403 {
		t.Fatalf("expected 403, got %d", envelope.Status)
	}
	if envelope.Data["subject"] != "user-1" || envelope.Data["target"] != "user-2" {
		t.Fatalf("expected the denial to name subject and target, got %v", envelope.Data)
	}
	if envelope.Data["field"] != authengine.ClaimRoles {
		t.Fatalf("expected the denial to name the role field, got %v", envelope.Data)
	}
}

func TestDenialPayloadDistinguishesAnAbsentTarget(t *testing.T) {
	t.Parallel()

	envelope := requireProblem(t,
		newGuard(t).Sub(owner(), nil),
		authengine.ProblemOwnershipDenied)

	if envelope.Data["target"] != nil {
		t.Fatalf("expected an absent target to stay nil rather than empty, got %v", envelope.Data["target"])
	}
}

func TestGuardLogsEveryDenialWhenASinkIsBound(t *testing.T) {
	t.Parallel()

	logs := mocks.NewInMemoryLoggerSink()
	clock := mocks.NewInMemorySystem(mocks.InMemorySystemOptions{Now: testhelper.FixedNow()})
	guard, err := authengine.NewGuard(authengine.GuardOptions{
		Problems: newProblems(t),
		Logs:     logs,
		Clock:    clock,
	})
	requireNoError(t, err)

	requireNoError(t, guard.Sub(owner(), new("user-1")))
	if len(logs.Records()) != 0 {
		t.Fatal("expected a passing guard not to log")
	}

	requireProblem(t, guard.Sub(owner(), new("user-2")), authengine.ProblemOwnershipDenied)
	records := logs.Records()
	if len(records) != 1 {
		t.Fatalf("expected one denial record, got %d", len(records))
	}
	if records[0].Level != interfaces.LogLevelInfo {
		t.Fatalf("expected an informational record, got %s", records[0].Level)
	}
	if records[0].Attributes["subject"] != "user-1" {
		t.Fatalf("expected the record to carry the denial payload, got %v", records[0].Attributes)
	}
}

func TestGuardKeepsDenyingWhenLoggingFails(t *testing.T) {
	t.Parallel()

	logs := mocks.NewInMemoryLoggerSink()
	logs.EnqueueResult(errFake)
	clock := mocks.NewInMemorySystem(mocks.InMemorySystemOptions{Now: testhelper.FixedNow()})
	guard, err := authengine.NewGuard(authengine.GuardOptions{
		Problems: newProblems(t), Logs: logs, Clock: clock,
	})
	requireNoError(t, err)

	// A telemetry failure must never turn a denial into a pass.
	requireProblem(t, guard.Sub(owner(), new("user-2")), authengine.ProblemOwnershipDenied)

	clock.EnqueueClockResult(time.Time{}, errFake)
	requireProblem(t, guard.Sub(owner(), new("user-2")), authengine.ProblemOwnershipDenied)
}

func TestRegisteredIsTheRealOnboardingDefault(t *testing.T) {
	t.Parallel()

	guard := newGuard(t)

	registered := authengine.NewClaimMapper().Map(authengine.Claims{
		authengine.ClaimSubject: "user-1",
		"alcohol_zinc":          "true",
	})
	requireNoError(t, guard.Registered(registered, "alcohol-zinc"))

	envelope := requireProblem(t,
		guard.Registered(owner(), "alcohol-zinc"),
		authengine.ProblemRegistrationMissing)
	if envelope.Data["claim"] != "alcohol_zinc" {
		t.Fatalf("expected the failure to name the derived claim, got %v", envelope.Data)
	}

	// Registration on one backend implies nothing about another.
	requireProblem(t,
		guard.Registered(registered, "nitroso-tin"),
		authengine.ProblemRegistrationMissing)
}

func TestClaimScopeCheckerReadsEveryClaimShape(t *testing.T) {
	t.Parallel()

	checker := authengine.ClaimScopeChecker{}
	principal := authengine.NewClaimMapper().Map(authengine.Claims{
		authengine.ClaimSubject: "user-1",
		authengine.ClaimRoles:   []any{"admin"},
		authengine.ClaimScope:   "read:booking write:booking",
		"tenant_groups":         []any{"finance"},
	})

	if got := checker.Scope(principal, authengine.ClaimRoles); len(got) != 1 || got[0] != "admin" {
		t.Fatalf("expected the mapped roles, got %v", got)
	}
	if got := checker.Scope(principal, authengine.ClaimScope); len(got) != 2 {
		t.Fatalf("expected the mapped scopes, got %v", got)
	}
	if got := checker.Scope(principal, "tenant_groups"); len(got) != 1 || got[0] != "finance" {
		t.Fatalf("expected an arbitrary claim to be readable, got %v", got)
	}
	if got := checker.Scope(principal, "absent"); len(got) != 0 {
		t.Fatalf("expected an absent claim to read as empty, got %v", got)
	}
	if !checker.HasAny(principal, "tenant_groups", []string{"finance", "ops"}) {
		t.Fatal("expected HasAny to read an arbitrary claim")
	}
	if !checker.HasAll(principal, authengine.ClaimScope, []string{"read:booking", "write:booking"}) {
		t.Fatal("expected HasAll to read the mapped scopes")
	}
	if checker.HasAll(principal, authengine.ClaimScope, []string{"read:booking", "delete:booking"}) {
		t.Fatal("expected HasAll to fail on a missing value")
	}
}

// countingChecker is a custom ScopeChecker proving the seam is honoured.
type countingChecker struct {
	calls *int
}

func (c countingChecker) Scope(_ authengine.Principal, _ string) []string {
	*c.calls++
	return []string{"custom"}
}

func (c countingChecker) HasAny(principal authengine.Principal, field string, _ []string) bool {
	c.Scope(principal, field)
	return true
}

func (c countingChecker) HasAll(principal authengine.Principal, field string, _ []string) bool {
	c.Scope(principal, field)
	return false
}

func TestGuardUsesTheSuppliedScopeChecker(t *testing.T) {
	t.Parallel()

	calls := 0
	guard, err := authengine.NewGuard(authengine.GuardOptions{
		Problems: newProblems(t),
		Checker:  countingChecker{calls: &calls},
	})
	requireNoError(t, err)

	requireNoError(t, guard.SubOrAny(owner(), nil, "anything"))
	requireProblem(t, guard.SubOrAll(owner(), nil, "anything"), authengine.ProblemOwnershipDenied)
	if calls == 0 {
		t.Fatal("expected the supplied checker to be consulted")
	}
}
