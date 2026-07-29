package authengine_test

import (
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
)

func TestRegistrationClaimFollowsTheFamilyConvention(t *testing.T) {
	t.Parallel()

	cases := []struct {
		backend string
		want    string
	}{
		{backend: "alcohol-zinc", want: "alcohol_zinc"},
		{backend: "Alcohol Zinc", want: "alcohol_zinc"},
		{backend: "nitroso-tin", want: "nitroso_tin"},
		{backend: "Zinc", want: "zinc"},
	}

	for _, testCase := range cases {
		t.Run(testCase.backend, func(t *testing.T) {
			t.Parallel()

			if got := authengine.RegistrationClaim(testCase.backend); got != testCase.want {
				t.Fatalf("expected %q, got %q", testCase.want, got)
			}
		})
	}
}

func TestClaimMapperMapsTheFullIdentity(t *testing.T) {
	t.Parallel()

	expiry := time.Unix(1_800_000_000, 0).UTC()
	claims := authengine.Claims{
		authengine.ClaimSubject:       "user-1",
		authengine.ClaimIssuer:        "https://issuer.invalid",
		authengine.ClaimAudience:      []any{"alcohol-zinc"},
		authengine.ClaimUsername:      "owner",
		authengine.ClaimEmail:         "owner@example.invalid",
		authengine.ClaimEmailVerified: true,
		authengine.ClaimRoles:         []any{"admin", "tin"},
		authengine.ClaimScope:         "read:booking write:booking",
		authengine.ClaimHomeLandscape: "lapras",
		authengine.ClaimExpiry:        float64(expiry.Unix()),
		"alcohol_zinc":                "true",
	}

	principal := authengine.NewClaimMapper().Map(claims)

	if principal.Subject != "user-1" || principal.Issuer != "https://issuer.invalid" {
		t.Fatalf("expected subject and issuer to be mapped, got %+v", principal)
	}
	if principal.Username == nil || *principal.Username != "owner" {
		t.Fatalf("expected the username to be mapped, got %v", principal.Username)
	}
	if principal.Email == nil || *principal.Email != "owner@example.invalid" {
		t.Fatalf("expected the email to be mapped, got %v", principal.Email)
	}
	if !principal.EmailVerified {
		t.Fatal("expected the verified-email flag to be mapped")
	}
	if !principal.HasRole("admin") || principal.HasRole("field") {
		t.Fatalf("expected only the granted roles, got %v", principal.Roles)
	}
	if !principal.HasScope("read:booking") || principal.HasScope("delete:booking") {
		t.Fatalf("expected only the granted scopes, got %v", principal.Scopes)
	}
	if principal.HomeLandscape == nil || *principal.HomeLandscape != "lapras" {
		t.Fatalf("expected the home landscape to be mapped, got %v", principal.HomeLandscape)
	}
	if !principal.ExpiresAt.Equal(expiry) {
		t.Fatalf("expected expiry %s, got %s", expiry, principal.ExpiresAt)
	}
	if len(principal.Audience) != 1 || principal.Audience[0] != "alcohol-zinc" {
		t.Fatalf("expected the audience to be mapped, got %v", principal.Audience)
	}
	if !principal.Registered("alcohol-zinc") {
		t.Fatal("expected the registration claim to be recognised")
	}
	if principal.Registered("nitroso-tin") {
		t.Fatal("expected an absent registration claim to read as not registered")
	}
}

func TestClaimMapperKeepsAbsentClaimsAbsent(t *testing.T) {
	t.Parallel()

	principal := authengine.NewClaimMapper().Map(authengine.Claims{
		authengine.ClaimSubject: "user-1",
	})

	if principal.Username != nil || principal.Email != nil || principal.HomeLandscape != nil {
		t.Fatalf("expected absent optional claims to stay nil, got %+v", principal)
	}
	if principal.EmailVerified {
		t.Fatal("expected an absent verified-email claim to read as false")
	}
	if len(principal.Roles) != 0 || len(principal.Scopes) != 0 {
		t.Fatalf("expected no roles or scopes, got %v / %v", principal.Roles, principal.Scopes)
	}
	if !principal.ExpiresAt.IsZero() {
		t.Fatalf("expected an absent expiry to stay zero, got %s", principal.ExpiresAt)
	}
}

func TestClaimMapperHonoursConfiguredClaimNames(t *testing.T) {
	t.Parallel()

	mapper := authengine.ClaimMapper{
		RolesClaim:         "tenant_roles",
		ScopeClaim:         "tenant_scope",
		HomeLandscapeClaim: "tenant_home",
	}

	principal := mapper.Map(authengine.Claims{
		"tenant_roles": []any{"admin"},
		"tenant_scope": "read:all",
		"tenant_home":  "mew",
		// The family-default names must NOT be read when the mapper names others.
		authengine.ClaimRoles: []any{"root"},
	})

	if !principal.HasRole("admin") || principal.HasRole("root") {
		t.Fatalf("expected only the configured roles claim to be read, got %v", principal.Roles)
	}
	if !principal.HasScope("read:all") {
		t.Fatalf("expected the configured scope claim to be read, got %v", principal.Scopes)
	}
	if principal.HomeLandscape == nil || *principal.HomeLandscape != "mew" {
		t.Fatalf("expected the configured home claim to be read, got %v", principal.HomeLandscape)
	}
}

func TestClaimMapperFallsBackForBlankClaimNames(t *testing.T) {
	t.Parallel()

	// A partially configured mapper must still behave: M33 says a blank value is
	// unset, not a claim literally named "".
	principal := authengine.ClaimMapper{RolesClaim: "tenant_roles"}.Map(authengine.Claims{
		"tenant_roles":                []any{"admin"},
		authengine.ClaimScope:         "read:all",
		authengine.ClaimHomeLandscape: "lapras",
	})

	if !principal.HasRole("admin") {
		t.Fatalf("expected the configured roles claim, got %v", principal.Roles)
	}
	if !principal.HasScope("read:all") {
		t.Fatalf("expected the default scope claim to be read, got %v", principal.Scopes)
	}
	if principal.HomeLandscape == nil {
		t.Fatal("expected the default home-landscape claim to be read")
	}
}

func TestPrincipalClaimsAreIndependentOfTheSource(t *testing.T) {
	t.Parallel()

	claims := authengine.Claims{authengine.ClaimSubject: "user-1"}
	principal := authengine.NewClaimMapper().Map(claims)
	principal.Claims[authengine.ClaimSubject] = "user-2"

	if value, _ := claims.Text(authengine.ClaimSubject); value != "user-1" {
		t.Fatalf("expected the source claims to stay untouched, got %q", value)
	}
}
