package operator_test

import (
	"errors"
	"strings"
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
	require.Equal(t, "onboarding adapter result", check.Reason)
}

// TestCredentialPointerGrammarIsUnambiguousAndTraversalSafe exercises the
// schema-compatible grammar on every traversal and non-schema form, then pins
// the exact raw and escaped S10 mappings at their compatibility boundary.
func TestCredentialPointerGrammarIsUnambiguousAndTraversalSafe(t *testing.T) {
	base := []string{"diene", "pichu", "postgres", "neon", "production-a"}
	fields := []string{"platform", "landscape", "class", "vendor", "name"}

	invalidForms := []struct {
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
		{"leading_hyphen", "-neon", "safe path segment"},
		{"trailing_hyphen", "neon-", "safe path segment"},
		{"underscore", "bad_segment", "safe path segment"},
		{"overlength", strings.Repeat("a", 64), "safe path segment"},
	}
	for _, form := range invalidForms {
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

	for name, blank := range map[string]string{
		"empty": "",
		"space": " ",
		"tabs":  " \t ",
		"line":  "\n",
	} {
		t.Run("blank_"+name, func(t *testing.T) {
			_, actualErr := provideraccount.CredentialPointerPath(
				blank, "pichu", "postgres", "neon", "production-a",
			)
			require.ErrorIs(t, actualErr, provideraccount.ErrInvalidCredentialPointer)
			require.Contains(t, actualErr.Error(), "must be nonblank")
		})
	}

	// The original collision witnesses are both schema-valid. They now receive
	// distinct escaped components instead of collapsing onto one raw component.
	collisionWitnesses := []struct {
		account provideraccount.Account
		want    string
	}{
		{
			account: provideraccount.Account{Vendor: "a", Name: "b-account-c"},
			want:    "/diene/pichu/postgres/_pa_a_b-account-c",
		},
		{
			account: provideraccount.Account{Vendor: "a-account-b", Name: "c"},
			want:    "/diene/pichu/postgres/_pa_a-account-b_c",
		},
	}
	collisionPaths := make([]string, 0, len(collisionWitnesses))
	for _, witness := range collisionWitnesses {
		actual, err := provideraccount.CredentialPointerPath(
			"diene", "pichu", "postgres", witness.account.Vendor, witness.account.Name,
		)
		require.NoError(t, err)
		require.Equal(t, witness.want, actual)
		collisionPaths = append(collisionPaths, actual)
	}
	require.NotEqual(t, collisionPaths[0], collisionPaths[1])

	// Ordinary and delimiter-shaped-but-unambiguous inputs retain their exact
	// legacy bytes. The 63-byte name makes the tempting alternate split invalid,
	// so even that internal delimiter does not trigger an unnecessary escape.
	longName := strings.Repeat("z", 63)
	compatible := []struct {
		vendor string
		name   string
		want   string
	}{
		{"neon", "production-a-2", "/diene/pichu/postgres/neon-account-production-a-2"},
		{"account", "prod", "/diene/pichu/postgres/account-account-prod"},
		{"neon", "account", "/diene/pichu/postgres/neon-account-account"},
		{"account-prod", "account", "/diene/pichu/postgres/account-prod-account-account"},
		{"a--account-b", "c", "/diene/pichu/postgres/a--account-b-account-c"},
		{"a-account-b", longName, "/diene/pichu/postgres/a-account-b-account-" + longName},
	}
	for _, test := range compatible {
		actual, err := provideraccount.CredentialPointerPath("diene", "pichu", "postgres", test.vendor, test.name)
		require.NoError(t, err)
		require.Equal(t, test.want, actual)
	}

	// Schema-valid account spellings that create a second valid decomposition
	// are accepted and encoded, never rejected or normalized.
	accountSpellings := []struct {
		vendor string
		name   string
		want   string
	}{
		{"neon", "account-prod", "/diene/pichu/postgres/_pa_neon_account-prod"},
		{"prod-account", "blue", "/diene/pichu/postgres/_pa_prod-account_blue"},
	}
	for _, test := range accountSpellings {
		actual, err := provideraccount.CredentialPointerPath("diene", "pichu", "postgres", test.vendor, test.name)
		require.NoError(t, err)
		require.Equal(t, test.want, actual)
	}

	// Lowercase input is accepted while its uppercase spelling is rejected: the
	// grammar never case-folds distinct spellings onto one pointer.
	lower, err := provideraccount.CredentialPointerPath("diene", "pichu", "postgres", "neon", "prod")
	require.NoError(t, err)
	require.Equal(t, "/diene/pichu/postgres/neon-account-prod", lower)
	_, upper := provideraccount.CredentialPointerPath("diene", "pichu", "postgres", "neon", "Prod")
	require.ErrorIs(t, upper, provideraccount.ErrInvalidCredentialPointer)
}

// TestSafeSegmentGrammarIsConsistentAcrossResolutionAndRegistry proves the full
// committed account domain is accepted by both entry points and every
// non-schema form retains its errors.Is/errors.As refusal category and context.
func TestSafeSegmentGrammarIsConsistentAcrossResolutionAndRegistry(t *testing.T) {
	accepted := []provideraccount.Account{
		{Vendor: "account", Name: "account"},
		{Vendor: "neon", Name: "account-prod"},
		{Vendor: "prod-account", Name: "blue"},
		{Vendor: "a-account-b", Name: "c"},
		{Vendor: "a", Name: "b-account-c"},
		{Vendor: "0", Name: strings.Repeat("z", 63)},
	}
	for _, account := range accepted {
		t.Run("accept_"+account.Vendor+"_"+account.Name, func(t *testing.T) {
			require.NoError(t, provideraccount.ValidateRegistry([]provideraccount.Account{account}))
			actual, err := provideraccount.Resolve(
				provideraccount.ModuleAccountSelector(account),
				[]provideraccount.Account{account},
			)
			require.NoError(t, err)
			require.Equal(t, account, actual)
		})
	}

	invalid := []struct {
		name           string
		account        provideraccount.Account
		resolutionKind provideraccount.ResolutionKind
		resolutionIs   error
	}{
		{"empty_vendor", provideraccount.Account{Vendor: "", Name: "prod"}, provideraccount.ResolutionInvalidSelector, provideraccount.ErrInvalidSelector},
		{"empty_name", provideraccount.Account{Vendor: "neon", Name: ""}, provideraccount.ResolutionSelectorRequired, provideraccount.ErrSelectorRequired},
		{"whitespace", provideraccount.Account{Vendor: "neon", Name: " \t "}, provideraccount.ResolutionSelectorRequired, provideraccount.ErrSelectorRequired},
		{"dot", provideraccount.Account{Vendor: "..", Name: "prod"}, provideraccount.ResolutionInvalidSelector, provideraccount.ErrInvalidSelector},
		{"slash", provideraccount.Account{Vendor: "ne/on", Name: "prod"}, provideraccount.ResolutionInvalidSelector, provideraccount.ErrInvalidSelector},
		{"backslash", provideraccount.Account{Vendor: "neon", Name: `bad\seg`}, provideraccount.ResolutionInvalidSelector, provideraccount.ErrInvalidSelector},
		{"percent_escape", provideraccount.Account{Vendor: "neon", Name: "bad%2fseg"}, provideraccount.ResolutionInvalidSelector, provideraccount.ErrInvalidSelector},
		{"uppercase", provideraccount.Account{Vendor: "Neon", Name: "prod"}, provideraccount.ResolutionInvalidSelector, provideraccount.ErrInvalidSelector},
		{"leading_hyphen", provideraccount.Account{Vendor: "-neon", Name: "prod"}, provideraccount.ResolutionInvalidSelector, provideraccount.ErrInvalidSelector},
		{"trailing_hyphen", provideraccount.Account{Vendor: "neon", Name: "prod-"}, provideraccount.ResolutionInvalidSelector, provideraccount.ErrInvalidSelector},
		{"underscore", provideraccount.Account{Vendor: "neon", Name: "bad_name"}, provideraccount.ResolutionInvalidSelector, provideraccount.ErrInvalidSelector},
		{"overlength", provideraccount.Account{Vendor: "neon", Name: strings.Repeat("a", 64)}, provideraccount.ResolutionInvalidSelector, provideraccount.ErrInvalidSelector},
	}
	for _, test := range invalid {
		t.Run("reject_"+test.name, func(t *testing.T) {
			registryErr := provideraccount.ValidateRegistry([]provideraccount.Account{test.account})
			require.ErrorIs(t, registryErr, provideraccount.ErrInvalidRegistry)
			require.NotErrorIs(t, registryErr, provideraccount.ErrDuplicateNameWithinVendor)
			var typedRegistryErr *provideraccount.RegistryError
			require.ErrorAs(t, registryErr, &typedRegistryErr)
			require.Equal(t, test.account.Vendor, typedRegistryErr.Vendor)
			require.Equal(t, test.account.Name, typedRegistryErr.Name)

			_, resolutionErr := provideraccount.Resolve(provideraccount.ModuleAccountSelector{
				Vendor: test.account.Vendor,
				Name:   test.account.Name,
			}, accepted)
			require.ErrorIs(t, resolutionErr, provideraccount.ErrUnresolved)
			require.ErrorIs(t, resolutionErr, test.resolutionIs)
			var typedResolutionErr *provideraccount.ResolutionError
			require.ErrorAs(t, resolutionErr, &typedResolutionErr)
			require.Equal(t, test.resolutionKind, typedResolutionErr.Kind)
			require.Equal(t, test.account.Vendor, typedResolutionErr.Vendor)
			require.Equal(t, test.account.Name, typedResolutionErr.Name)
		})
	}
}

// TestCredentialPointerMappingIsDeterministicInjectiveAndReversible checks the
// mapping as a property over the Cartesian product of representative schema
// labels, including boundary lengths and every delimiter placement class.
func TestCredentialPointerMappingIsDeterministicInjectiveAndReversible(t *testing.T) {
	labels := []string{
		"0",
		"a",
		"b",
		"account",
		"account-prod",
		"prod-account",
		"myaccount",
		"a-account-b",
		"b-account-c",
		"a--account-b",
		"b-account--c",
		"x-account-y-account-z",
		strings.Repeat("z", 63),
	}
	const pathPrefix = "/diene/pichu/postgres/"
	seen := make(map[string]provideraccount.Account, len(labels)*len(labels))

	for _, vendor := range labels {
		for _, name := range labels {
			identity := provideraccount.Account{Vendor: vendor, Name: name}
			first, err := provideraccount.CredentialPointerPath("diene", "pichu", "postgres", vendor, name)
			require.NoError(t, err)
			second, err := provideraccount.CredentialPointerPath("diene", "pichu", "postgres", vendor, name)
			require.NoError(t, err)
			require.Equal(t, first, second, "mapping must be deterministic for %#v", identity)

			component := strings.TrimPrefix(first, pathPrefix)
			require.NotEqual(t, first, component, "pointer must retain its coordinate prefix")
			decoded, ok := decodeCredentialPointerComponentForTest(component)
			require.True(t, ok, "component %q must be reversible", component)
			require.Equal(t, identity, decoded)

			if prior, exists := seen[first]; exists {
				require.Equal(t, prior, identity, "distinct identities must not share pointer %q", first)
			}
			seen[first] = identity
		}
	}
	require.Len(t, seen, len(labels)*len(labels))
}

func decodeCredentialPointerComponentForTest(component string) (provideraccount.Account, bool) {
	const (
		escapedPrefix = "_pa_"
		delimiter     = "-account-"
	)
	if payload, escaped := strings.CutPrefix(component, escapedPrefix); escaped {
		separator := strings.IndexByte(payload, '_')
		if separator <= 0 || separator == len(payload)-1 || strings.Contains(payload[separator+1:], "_") {
			return provideraccount.Account{}, false
		}
		vendor, name := payload[:separator], payload[separator+1:]
		if !isProviderAccountLabelForTest(vendor) || !isProviderAccountLabelForTest(name) {
			return provideraccount.Account{}, false
		}
		return provideraccount.Account{Vendor: vendor, Name: name}, true
	}

	var decoded provideraccount.Account
	validSplits := 0
	for searchFrom := 0; searchFrom < len(component); {
		relativeStart := strings.Index(component[searchFrom:], delimiter)
		if relativeStart < 0 {
			break
		}
		delimiterStart := searchFrom + relativeStart
		vendor := component[:delimiterStart]
		name := component[delimiterStart+len(delimiter):]
		if isProviderAccountLabelForTest(vendor) && isProviderAccountLabelForTest(name) {
			decoded = provideraccount.Account{Vendor: vendor, Name: name}
			validSplits++
		}
		searchFrom = delimiterStart + 1
	}
	return decoded, validSplits == 1
}

func isProviderAccountLabelForTest(value string) bool {
	if len(value) == 0 || len(value) > 63 || value[0] == '-' || value[len(value)-1] == '-' {
		return false
	}
	for index := range len(value) {
		character := value[index]
		if (character < 'a' || character > 'z') && (character < '0' || character > '9') && character != '-' {
			return false
		}
	}
	return true
}
