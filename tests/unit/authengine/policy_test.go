package authengine_test

import (
	"testing"

	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
)

// samplePolicies mirror the reference stack's registry: an admin-only policy and a
// two-role alternative.
func samplePolicies() authengine.PolicySet {
	return authengine.PolicySet{
		"OnlyAdmin": {Kind: authengine.PolicyAll, Field: authengine.ClaimRoles, Target: []string{"admin"}},
		"AdminOrTin": {
			Kind: authengine.PolicyAny, Field: authengine.ClaimRoles, Target: []string{"admin", "tin"},
		},
		"Broken": {Kind: "sometimes", Field: authengine.ClaimRoles, Target: []string{"admin"}},
	}
}

func TestPolicySetNamesAreSorted(t *testing.T) {
	t.Parallel()

	names := samplePolicies().Names()
	if len(names) != 3 || names[0] != "AdminOrTin" || names[2] != "OnlyAdmin" {
		t.Fatalf("expected sorted policy names, got %v", names)
	}
}

func TestPolicyAuthorizesByQuantifier(t *testing.T) {
	t.Parallel()

	guard := newGuard(t)
	policies := samplePolicies()

	requireNoError(t, guard.Policy(admin(), policies, "OnlyAdmin"))
	requireNoError(t, guard.Policy(admin(), policies, "AdminOrTin"))
	requireProblem(t, guard.Policy(owner(), policies, "OnlyAdmin"), authengine.ProblemOwnershipDenied)
	requireProblem(t, guard.Policy(owner(), policies, "AdminOrTin"), authengine.ProblemOwnershipDenied)
}

func TestPolicyFailsClosedOnAnUnrecognisedQuantifier(t *testing.T) {
	t.Parallel()

	// A typo in a config quantifier must deny rather than default to permissive.
	requireProblem(t,
		newGuard(t).Policy(admin(), samplePolicies(), "Broken"),
		authengine.ProblemOwnershipDenied)
}

func TestPolicyRefusesAnUndeclaredName(t *testing.T) {
	t.Parallel()

	envelope := requireProblem(t,
		newGuard(t).Policy(admin(), samplePolicies(), "NeverDeclared"),
		authengine.ProblemPolicyUnknown)

	if envelope.Status != 500 {
		t.Fatalf("expected an undeclared policy to be a configuration failure, got %d", envelope.Status)
	}
	declared, ok := envelope.Data["declared"].([]string)
	if !ok || len(declared) != 3 {
		t.Fatalf("expected the failure to name the declared policies, got %v", envelope.Data)
	}
}

func TestPolicyDenialNamesTheQuantifierAndRequirement(t *testing.T) {
	t.Parallel()

	envelope := requireProblem(t,
		newGuard(t).Policy(owner(), samplePolicies(), "OnlyAdmin"),
		authengine.ProblemOwnershipDenied)

	if envelope.Data["policy"] != "OnlyAdmin" {
		t.Fatalf("expected the denial to name the policy, got %v", envelope.Data)
	}
	if envelope.Data["kind"] != string(authengine.PolicyAll) {
		t.Fatalf("expected the denial to name the quantifier, got %v", envelope.Data)
	}
}
