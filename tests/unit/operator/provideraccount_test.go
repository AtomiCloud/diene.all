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
		require.Contains(t, actualErr.Error(), "one path segment")

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
