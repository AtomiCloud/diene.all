package authengine_test

import (
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
)

func TestClaimsTextReadsStringClaims(t *testing.T) {
	t.Parallel()

	claims := authengine.Claims{authengine.ClaimSubject: "user-1", "count": 3}

	if value, found := claims.Text(authengine.ClaimSubject); !found || value != "user-1" {
		t.Fatalf("expected sub 'user-1', got %q (found=%t)", value, found)
	}
	if _, found := claims.Text("count"); found {
		t.Fatal("expected a non-string claim to read as absent")
	}
	if _, found := claims.Text("missing"); found {
		t.Fatal("expected a missing claim to read as absent")
	}
}

func TestClaimsFlagAcceptsBothWireEncodings(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name  string
		value any
		want  bool
		found bool
	}{
		{name: "native true", value: true, want: true, found: true},
		{name: "native false", value: false, want: false, found: true},
		{name: "string true", value: "true", want: true, found: true},
		{name: "string false", value: "false", want: false, found: true},
		{name: "other string", value: "yes", want: false, found: false},
		{name: "wrong type", value: 1, want: false, found: false},
	}

	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			t.Parallel()

			claims := authengine.Claims{authengine.ClaimEmailVerified: testCase.value}
			value, found := claims.Flag(authengine.ClaimEmailVerified)
			if value != testCase.want || found != testCase.found {
				t.Fatalf("expected (%t, %t), got (%t, %t)", testCase.want, testCase.found, value, found)
			}
		})
	}
}

func TestClaimsFlagReportsAbsentClaim(t *testing.T) {
	t.Parallel()

	empty := authengine.Claims{}

	if _, found := empty.Flag("alcohol_zinc"); found {
		t.Fatal("expected an absent claim to be distinguishable from a false claim")
	}
}

func TestClaimsListNormalizesEveryEncoding(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name  string
		value any
		want  []string
		found bool
	}{
		{name: "string list", value: []string{"admin"}, want: []string{"admin"}, found: true},
		{name: "single string", value: "admin", want: []string{"admin"}, found: true},
		{name: "json list", value: []any{"admin", "tin"}, want: []string{"admin", "tin"}, found: true},
		{name: "mixed json list", value: []any{"admin", 7}, want: []string{"admin"}, found: true},
		{name: "wrong type", value: 7, want: nil, found: false},
	}

	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			t.Parallel()

			claims := authengine.Claims{authengine.ClaimRoles: testCase.value}
			value, found := claims.List(authengine.ClaimRoles)
			if found != testCase.found {
				t.Fatalf("expected found=%t, got %t", testCase.found, found)
			}
			if len(value) != len(testCase.want) {
				t.Fatalf("expected %v, got %v", testCase.want, value)
			}
			for index := range value {
				if value[index] != testCase.want[index] {
					t.Fatalf("expected %v, got %v", testCase.want, value)
				}
			}
		})
	}
}

func TestClaimsListCopiesTheBackingSlice(t *testing.T) {
	t.Parallel()

	backing := []string{"admin"}
	claims := authengine.Claims{authengine.ClaimRoles: backing}

	value, _ := claims.List(authengine.ClaimRoles)
	value[0] = "mutated"

	if backing[0] != "admin" {
		t.Fatal("expected List to copy rather than alias the claim value")
	}
}

func TestClaimsSpaceSplitsScopeClaims(t *testing.T) {
	t.Parallel()

	claims := authengine.Claims{authengine.ClaimScope: "read:booking  write:booking"}

	value, found := claims.Space(authengine.ClaimScope)
	if !found || len(value) != 2 || value[0] != "read:booking" || value[1] != "write:booking" {
		t.Fatalf("expected two scopes, got %v (found=%t)", value, found)
	}
	empty := authengine.Claims{}
	if _, found := empty.Space(authengine.ClaimScope); found {
		t.Fatal("expected an absent scope claim to read as absent")
	}
}

func TestClaimsInstantAcceptsEveryNumericEncoding(t *testing.T) {
	t.Parallel()

	want := time.Unix(1_800_000_000, 0).UTC()
	cases := []struct {
		name  string
		value any
		found bool
	}{
		{name: "float64", value: float64(1_800_000_000), found: true},
		{name: "int64", value: int64(1_800_000_000), found: true},
		{name: "int", value: 1_800_000_000, found: true},
		{name: "string", value: "1800000000", found: false},
	}

	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			t.Parallel()

			claims := authengine.Claims{authengine.ClaimExpiry: testCase.value}
			value, found := claims.Instant(authengine.ClaimExpiry)
			if found != testCase.found {
				t.Fatalf("expected found=%t, got %t", testCase.found, found)
			}
			if testCase.found && !value.Equal(want) {
				t.Fatalf("expected %s, got %s", want, value)
			}
		})
	}
}

func TestClaimsCloneIsIndependent(t *testing.T) {
	t.Parallel()

	claims := authengine.Claims{authengine.ClaimSubject: "user-1"}
	clone := claims.Clone()
	clone[authengine.ClaimSubject] = "user-2"

	if value, _ := claims.Text(authengine.ClaimSubject); value != "user-1" {
		t.Fatalf("expected the source claims to stay untouched, got %q", value)
	}
	if authengine.Claims(nil).Clone() != nil {
		t.Fatal("expected a nil claim set to clone to nil")
	}
}
