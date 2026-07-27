package operator_test

import (
	"errors"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/AtomiCloud/diene.fleet-operator/lib/operator/provideraccount"
)

func TestResolveProviderAccountRequiresAnExplicitSingleMatch(t *testing.T) {
	accounts := []provideraccount.Account{
		{Vendor: "neon", Name: "production-a"},
		{Vendor: "neon", Name: "production-b"},
		{Vendor: "upstash", Name: "production-a"},
	}

	actual, err := provideraccount.Resolve(provideraccount.ModuleAccountSelector{Vendor: "neon", Name: "production-b"}, accounts)
	require.NoError(t, err)
	require.Equal(t, provideraccount.Account{Vendor: "neon", Name: "production-b"}, actual)

	t.Run("absent selector refuses without a default", func(t *testing.T) {
		_, actualErr := provideraccount.Resolve(provideraccount.ModuleAccountSelector{Vendor: "neon"}, accounts)
		require.ErrorIs(t, actualErr, provideraccount.ErrUnresolved)
		require.ErrorIs(t, actualErr, provideraccount.ErrSelectorRequired)
		var resolutionError *provideraccount.ResolutionError
		require.ErrorAs(t, actualErr, &resolutionError)
		require.Equal(t, provideraccount.ResolutionSelectorRequired, resolutionError.Kind)
	})

	t.Run("malformed selector refuses", func(t *testing.T) {
		_, actualErr := provideraccount.Resolve(provideraccount.ModuleAccountSelector{Vendor: "ne/on", Name: "production-a"}, accounts)
		require.ErrorIs(t, actualErr, provideraccount.ErrUnresolved)
		require.ErrorIs(t, actualErr, provideraccount.ErrInvalidSelector)
		require.Contains(t, actualErr.Error(), "safe path segment")

		_, actualErr = provideraccount.Resolve(provideraccount.ModuleAccountSelector{Vendor: "neon", Name: "production/a"}, accounts)
		require.ErrorIs(t, actualErr, provideraccount.ErrInvalidSelector)
	})

	t.Run("missing named account refuses", func(t *testing.T) {
		_, actualErr := provideraccount.Resolve(provideraccount.ModuleAccountSelector{Vendor: "neon", Name: "missing"}, accounts)
		require.ErrorIs(t, actualErr, provideraccount.ErrUnresolved)
		require.ErrorIs(t, actualErr, provideraccount.ErrAccountNotFound)
	})

	t.Run("duplicate match is ambiguous", func(t *testing.T) {
		_, actualErr := provideraccount.Resolve(provideraccount.ModuleAccountSelector{Vendor: "neon", Name: "production-a"}, []provideraccount.Account{
			{Vendor: "neon", Name: "production-a"},
			{Vendor: "neon", Name: "production-a"},
		})
		require.ErrorIs(t, actualErr, provideraccount.ErrUnresolved)
		require.ErrorIs(t, actualErr, provideraccount.ErrAmbiguousAccount)
	})

	t.Run("unknown resolution kind matches no concrete sentinel", func(t *testing.T) {
		actualErr := &provideraccount.ResolutionError{Kind: "unknown"}
		require.True(t, errors.Is(actualErr, provideraccount.ErrUnresolved))
		require.False(t, errors.Is(actualErr, provideraccount.ErrAccountNotFound))
	})
}

func TestValidateProviderAccountRegistryIdentityLaw(t *testing.T) {
	require.NoError(t, provideraccount.ValidateRegistry([]provideraccount.Account{
		{Vendor: "neon", Name: "production-a"},
		{Vendor: "upstash", Name: "production-a"},
	}))

	err := provideraccount.ValidateRegistry([]provideraccount.Account{
		{Vendor: "neon", Name: "production-a"},
		{Vendor: "neon", Name: "production-a"},
	})
	require.ErrorIs(t, err, provideraccount.ErrInvalidRegistry)
	require.ErrorIs(t, err, provideraccount.ErrDuplicateNameWithinVendor)
	require.ErrorIs(t, err, provideraccount.ErrDuplicateVendorNameIdentity)
	require.Contains(t, err.Error(), "fleet-wide unique")
	var registryError *provideraccount.RegistryError
	require.ErrorAs(t, err, &registryError)
	require.Equal(t, "neon", registryError.Vendor)

	for _, account := range []provideraccount.Account{
		{Vendor: " ", Name: "production-a"},
		{Vendor: "ne/on", Name: "production-a"},
		{Vendor: "neon", Name: " "},
		{Vendor: "neon", Name: "production/a"},
	} {
		t.Run(account.Vendor+account.Name, func(t *testing.T) {
			actualErr := provideraccount.ValidateRegistry([]provideraccount.Account{account})
			require.ErrorIs(t, actualErr, provideraccount.ErrInvalidRegistry)
			require.NotErrorIs(t, actualErr, provideraccount.ErrDuplicateNameWithinVendor)
		})
	}
}

func TestCredentialPointerPathIsExactAndRejectsMalformedSegments(t *testing.T) {
	actual, err := provideraccount.CredentialPointerPath("diene", "pichu", "postgres", "neon", "production-a")
	require.NoError(t, err)
	require.Equal(t, "/diene/pichu/postgres/neon-account-production-a", actual)

	segments := []string{"diene", "pichu", "postgres", "neon", "production-a"}
	for index, field := range []string{"platform", "landscape", "class", "vendor", "name"} {
		t.Run("blank_"+field, func(t *testing.T) {
			invalid := append([]string(nil), segments...)
			invalid[index] = " \t "
			_, actualErr := provideraccount.CredentialPointerPath(invalid[0], invalid[1], invalid[2], invalid[3], invalid[4])
			require.ErrorIs(t, actualErr, provideraccount.ErrInvalidCredentialPointer)
			var pointerError *provideraccount.CredentialPointerError
			require.ErrorAs(t, actualErr, &pointerError)
			require.Equal(t, field, pointerError.Field)
			require.Contains(t, actualErr.Error(), "must be nonblank")
		})

		t.Run("slash_"+field, func(t *testing.T) {
			invalid := append([]string(nil), segments...)
			invalid[index] = "bad/segment"
			_, actualErr := provideraccount.CredentialPointerPath(invalid[0], invalid[1], invalid[2], invalid[3], invalid[4])
			require.ErrorIs(t, actualErr, provideraccount.ErrInvalidCredentialPointer)
		})
	}

	check := provideraccount.OnboardingCheck{
		Account:        provideraccount.Account{Vendor: "neon", Name: "production-a"},
		Ready:          true,
		QuotaAvailable: true,
		Reason:         "onboarding adapter result",
	}
	require.True(t, check.Ready)
	require.True(t, check.QuotaAvailable)
}

// TestCredentialPointerGrammarIsUnambiguousAndTraversalSafe exercises the
// strict safe-segment grammar on every reserved and ambiguous form, applied
// uniformly to all five components, and proves the ordinary canonical inputs
// still round-trip to the exact S10 path.
func TestCredentialPointerGrammarIsUnambiguousAndTraversalSafe(t *testing.T) {
	base := []string{"diene", "pichu", "postgres", "neon", "production-a"}
	fields := []string{"platform", "landscape", "class", "vendor", "name"}

	// Each reserved form must be rejected in EVERY component with the same rule,
	// proving account-identity and pointer validation cannot disagree.
	reserved := []struct {
		name       string
		value      string
		wantReason string
	}{
		{"dot", ".", "safe path segment"},
		{"dotdot", "..", "safe path segment"},
		{"slash", "bad/seg", "safe path segment"},
		{"backslash", `bad\seg`, "safe path segment"},
		{"percent_escape_slash", "bad%2fseg", "safe path segment"},
		{"percent_escape_dot", "bad%2eseg", "safe path segment"},
		{"internal_space", "bad seg", "safe path segment"},
		{"tab", "bad\tseg", "safe path segment"},
		{"newline", "bad\nseg", "safe path segment"},
		{"uppercase", "Neon", "safe path segment"},
		{"unicode_letter", "néon", "safe path segment"},
		{"reserved_account_token", "b-account-c", `reserved "account" delimiter token`},
	}
	for _, form := range reserved {
		for index, field := range fields {
			t.Run(form.name+"_in_"+field, func(t *testing.T) {
				invalid := append([]string(nil), base...)
				invalid[index] = form.value
				_, actualErr := provideraccount.CredentialPointerPath(invalid[0], invalid[1], invalid[2], invalid[3], invalid[4])
				require.ErrorIs(t, actualErr, provideraccount.ErrInvalidCredentialPointer)
				var pointerError *provideraccount.CredentialPointerError
				require.ErrorAs(t, actualErr, &pointerError)
				require.Equal(t, field, pointerError.Field)
				require.Contains(t, actualErr.Error(), form.wantReason)
			})
		}
	}

	// Blank / whitespace-only forms are rejected, never trimmed onto a canonical
	// neighbour.
	for _, blank := range []string{"", " ", " \t ", "\n"} {
		t.Run("blank_"+blank, func(t *testing.T) {
			_, actualErr := provideraccount.CredentialPointerPath(blank, "pichu", "postgres", "neon", "production-a")
			require.ErrorIs(t, actualErr, provideraccount.ErrInvalidCredentialPointer)
			require.Contains(t, actualErr.Error(), "must be nonblank")
		})
	}

	// The two witness identities from the review must both be rejected outright,
	// so they can never resolve to the shared /diene/pichu/postgres/a-account-b-account-c.
	_, nameCollision := provideraccount.CredentialPointerPath("diene", "pichu", "postgres", "a", "b-account-c")
	require.ErrorIs(t, nameCollision, provideraccount.ErrInvalidCredentialPointer)
	var nameErr *provideraccount.CredentialPointerError
	require.ErrorAs(t, nameCollision, &nameErr)
	require.Equal(t, "name", nameErr.Field)

	_, vendorCollision := provideraccount.CredentialPointerPath("diene", "pichu", "postgres", "a-account-b", "c")
	require.ErrorIs(t, vendorCollision, provideraccount.ErrInvalidCredentialPointer)
	var vendorErr *provideraccount.CredentialPointerError
	require.ErrorAs(t, vendorCollision, &vendorErr)
	require.Equal(t, "vendor", vendorErr.Field)

	// Ordinary already-canonical inputs still produce the exact S10 path,
	// including hyphens and digits.
	exact, err := provideraccount.CredentialPointerPath("diene", "pichu", "postgres", "neon", "production-a-2")
	require.NoError(t, err)
	require.Equal(t, "/diene/pichu/postgres/neon-account-production-a-2", exact)

	// Lowercase input is accepted while its uppercase spelling is rejected: the
	// grammar never case-folds distinct spellings onto one pointer.
	lower, err := provideraccount.CredentialPointerPath("diene", "pichu", "postgres", "neon", "prod")
	require.NoError(t, err)
	require.Equal(t, "/diene/pichu/postgres/neon-account-prod", lower)
	_, upper := provideraccount.CredentialPointerPath("diene", "pichu", "postgres", "neon", "Prod")
	require.ErrorIs(t, upper, provideraccount.ErrInvalidCredentialPointer)
}

// TestSafeSegmentGrammarIsConsistentAcrossResolutionAndRegistry proves the same
// grammar governs selector resolution and registry validation, so the reserved
// delimiter token and traversal forms are refused there too under their own
// typed categories.
func TestSafeSegmentGrammarIsConsistentAcrossResolutionAndRegistry(t *testing.T) {
	accounts := []provideraccount.Account{{Vendor: "neon", Name: "production-a"}}

	t.Run("resolution refuses the reserved delimiter token", func(t *testing.T) {
		for _, selector := range []provideraccount.ModuleAccountSelector{
			{Vendor: "a-account-b", Name: "c"},
			{Vendor: "a", Name: "b-account-c"},
		} {
			_, actualErr := provideraccount.Resolve(selector, accounts)
			require.ErrorIs(t, actualErr, provideraccount.ErrUnresolved)
			require.ErrorIs(t, actualErr, provideraccount.ErrInvalidSelector)
			require.Contains(t, actualErr.Error(), `reserved "account" delimiter token`)
		}
	})

	t.Run("resolution refuses traversal and escape forms", func(t *testing.T) {
		for _, selector := range []provideraccount.ModuleAccountSelector{
			{Vendor: "..", Name: "production-a"},
			{Vendor: "neon", Name: `bad\seg`},
			{Vendor: "neon", Name: "bad%2fseg"},
			{Vendor: "Neon", Name: "production-a"},
		} {
			_, actualErr := provideraccount.Resolve(selector, accounts)
			require.ErrorIs(t, actualErr, provideraccount.ErrInvalidSelector)
		}
	})

	t.Run("registry refuses the reserved delimiter token and traversal forms", func(t *testing.T) {
		for _, account := range []provideraccount.Account{
			{Vendor: "a-account-b", Name: "c"},
			{Vendor: "a", Name: "b-account-c"},
			{Vendor: "..", Name: "production-a"},
			{Vendor: "neon", Name: `bad\seg`},
		} {
			actualErr := provideraccount.ValidateRegistry([]provideraccount.Account{account})
			require.ErrorIs(t, actualErr, provideraccount.ErrInvalidRegistry)
			require.NotErrorIs(t, actualErr, provideraccount.ErrDuplicateNameWithinVendor)
		}
	})
}
