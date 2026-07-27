package operator_test

import (
	"errors"
	"strings"
	"testing"
	"unicode/utf8"

	"github.com/AtomiCloud/diene.fleet-operator/lib/operator/derive"
	"github.com/stretchr/testify/require"
)

func TestDeriveNameIsDeterministicAndNormalizesEverySegment(t *testing.T) {
	coordinate := derive.LPSM{
		Landscape: " Production ",
		Platform:  " Fleet API ",
		Service:   " Billing ",
		Module:    " PostgreSQL ",
	}

	first, err := derive.Name(coordinate, deriveProfile(63, derive.OverflowReject))
	require.NoError(t, err)
	second, err := derive.Name(coordinate, deriveProfile(63, derive.OverflowReject))
	require.NoError(t, err)

	require.Equal(t, first, second)
	require.True(t, strings.HasPrefix(first, "production--fleet-api--billing--postgresql--"))
	require.LessOrEqual(t, len(first), 63)
}

func TestDeriveNameKeepsDistinctCoordinatesDistinct(t *testing.T) {
	profile := deriveProfile(100, derive.OverflowReject)
	base := derive.LPSM{Landscape: "prod", Platform: "platform", Service: "service", Module: "module"}
	caseOnly := base
	caseOnly.Service = "SERVICE"
	different := base
	different.Module = "other-module"

	baseName, err := derive.Name(base, profile)
	require.NoError(t, err)
	caseName, err := derive.Name(caseOnly, profile)
	require.NoError(t, err)
	differentName, err := derive.Name(different, profile)
	require.NoError(t, err)

	require.NotEqual(t, baseName, caseName, "the full raw coordinate protects normalization collisions")
	require.NotEqual(t, baseName, differentName)
}

func TestDeriveForkNameAddsInstanceAndGeneration(t *testing.T) {
	coordinate := derive.LPSM{Landscape: "prod", Platform: "platform", Service: "service", Module: "module"}
	profile := deriveProfile(100, derive.OverflowReject)

	name, err := derive.Name(coordinate, profile)
	require.NoError(t, err)
	forkZero, err := derive.ForkName(coordinate, "pr-42", 0, profile)
	require.NoError(t, err)
	forkOne, err := derive.ForkName(coordinate, "pr-42", 1, profile)
	require.NoError(t, err)
	otherInstance, err := derive.ForkName(coordinate, "pr-43", 1, profile)
	require.NoError(t, err)

	require.NotEqual(t, name, forkZero)
	require.NotEqual(t, forkZero, forkOne)
	require.NotEqual(t, forkOne, otherInstance)
	require.Contains(t, forkOne, "--fork--pr-42--1--")
}

func TestDeriveRejectsBlankAndUnnormalizableSegments(t *testing.T) {
	profile := deriveProfile(100, derive.OverflowReject)
	coordinate := derive.LPSM{Landscape: "landscape", Platform: "platform", Service: "service", Module: "module"}

	for field, value := range map[string]string{
		"landscape": " ",
		"platform":  "\t",
		"service":   "\n",
		"module":    "",
	} {
		t.Run(field, func(t *testing.T) {
			candidate := coordinate
			switch field {
			case "landscape":
				candidate.Landscape = value
			case "platform":
				candidate.Platform = value
			case "service":
				candidate.Service = value
			case "module":
				candidate.Module = value
			default:
				t.Fatalf("unexpected coordinate field %q", field)
			}
			_, err := derive.Name(candidate, profile)
			require.ErrorIs(t, err, derive.ErrBlankSegment)
			require.Contains(t, err.Error(), field)
		})
	}

	_, err := derive.ForkName(coordinate, " ", 1, profile)
	require.ErrorIs(t, err, derive.ErrBlankSegment)
	require.Contains(t, err.Error(), "instance")

	normalizerCause := errors.New("unsupported character")
	profile.Normalize = func(string) (string, error) { return "", normalizerCause }
	_, err = derive.Name(coordinate, profile)
	require.ErrorIs(t, err, derive.ErrUnnormalizable)
	require.ErrorIs(t, err, normalizerCause)

	profile.Normalize = func(string) (string, error) { return " \t", nil }
	_, err = derive.Name(coordinate, profile)
	require.ErrorIs(t, err, derive.ErrUnnormalizable)

	profile.Normalize = func(string) (string, error) { return string([]byte{0xff}), nil }
	_, err = derive.Name(coordinate, profile)
	require.ErrorIs(t, err, derive.ErrUnnormalizable)
}

func TestDeriveHonorsBoundaryBudgetAndExplicitOverflowPolicy(t *testing.T) {
	coordinate := derive.LPSM{Landscape: "landscape", Platform: "platform", Service: "service", Module: "module"}
	wide := deriveProfile(100, derive.OverflowReject)
	full, err := derive.Name(coordinate, wide)
	require.NoError(t, err)

	atBoundary := deriveProfile(len(full), derive.OverflowReject)
	name, err := derive.Name(coordinate, atBoundary)
	require.NoError(t, err)
	require.Equal(t, full, name)

	overflow := deriveProfile(len(full)-1, derive.OverflowReject)
	_, err = derive.Name(coordinate, overflow)
	require.ErrorIs(t, err, derive.ErrNameTooLong)

	trimmedProfile := deriveProfile(24, derive.OverflowTrim)
	trimmed, err := derive.Name(coordinate, trimmedProfile)
	require.NoError(t, err)
	require.Len(t, trimmed, trimmedProfile.MaxLength)
	require.True(t, strings.HasSuffix(trimmed, "--"+strings.Split(full, "--")[len(strings.Split(full, "--"))-1]))

	// A multi-byte normalized character may straddle the byte budget. The
	// explicit trim rule must back up to a valid UTF-8 boundary rather than emit
	// an invalid vendor name.
	unicodeCoordinate := coordinate
	unicodeCoordinate.Landscape = "éééé"
	unicodeProfile := trimmedProfile
	unicodeProfile.MaxLength = 25 // leaves seven bytes before the suffix: mid-rune
	unicodeProfile.Normalize = func(value string) (string, error) { return value, nil }
	unicodeName, err := derive.Name(unicodeCoordinate, unicodeProfile)
	require.NoError(t, err)
	require.True(t, utf8.ValidString(unicodeName))
	require.LessOrEqual(t, len(unicodeName), unicodeProfile.MaxLength)
}

func TestDeriveProfileAndGenerationValidationAreTyped(t *testing.T) {
	coordinate := derive.LPSM{Landscape: "landscape", Platform: "platform", Service: "service", Module: "module"}
	valid := deriveProfile(100, derive.OverflowReject)
	maximumDigest := valid
	maximumDigest.MaxLength = 200
	maximumDigest.DigestLength = 52
	_, err := derive.Name(coordinate, maximumDigest)
	require.NoError(t, err)

	profiles := []derive.Profile{
		{MaxLength: 0, Separator: "--", DigestLength: 16, Overflow: derive.OverflowReject, Normalize: valid.Normalize},
		{MaxLength: 100, Separator: " ", DigestLength: 16, Overflow: derive.OverflowReject, Normalize: valid.Normalize},
		{MaxLength: 100, Separator: "--", DigestLength: 0, Overflow: derive.OverflowReject, Normalize: valid.Normalize},
		{MaxLength: 100, Separator: "--", DigestLength: 53, Overflow: derive.OverflowReject, Normalize: valid.Normalize},
		{MaxLength: 100, Separator: "--", DigestLength: 16, Overflow: "unknown", Normalize: valid.Normalize},
		{MaxLength: 100, Separator: "--", DigestLength: 16, Overflow: derive.OverflowReject},
		{MaxLength: 18, Separator: "--", DigestLength: 16, Overflow: derive.OverflowReject, Normalize: valid.Normalize},
	}
	for _, profile := range profiles {
		validationErr := profile.Validate()
		require.ErrorIs(t, validationErr, derive.ErrInvalidProfile)
		var typed *derive.Error
		require.ErrorAs(t, validationErr, &typed)
		require.NotEmpty(t, typed.Field)
	}
	_, err = derive.Name(coordinate, profiles[5])
	require.ErrorIs(t, err, derive.ErrInvalidProfile)

	_, err = derive.ForkName(coordinate, "instance", -1, valid)
	require.ErrorIs(t, err, derive.ErrInvalidGeneration)
	require.Equal(t, "derive: blank segment", derive.ErrBlankSegment.Error())

	tooLong := deriveProfile(20, derive.OverflowReject)
	_, err = derive.Name(coordinate, tooLong)
	require.ErrorIs(t, err, derive.ErrNameTooLong)
	require.Contains(t, err.Error(), "limit 20")

	cause := errors.New("normalizer failed")
	badNormalizer := deriveProfile(100, derive.OverflowReject)
	badNormalizer.Normalize = func(string) (string, error) { return "", cause }
	_, err = derive.Name(coordinate, badNormalizer)
	require.ErrorIs(t, err, cause)
	require.Contains(t, err.Error(), "normalizer failed")
}

func deriveProfile(maxLength int, overflow derive.OverflowPolicy) derive.Profile {
	return derive.Profile{
		MaxLength:    maxLength,
		Separator:    "--",
		DigestLength: 16,
		Overflow:     overflow,
		Normalize: func(value string) (string, error) {
			return strings.ReplaceAll(strings.ToLower(strings.TrimSpace(value)), " ", "-"), nil
		},
	}
}
