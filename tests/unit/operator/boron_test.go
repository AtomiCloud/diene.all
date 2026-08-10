package operator_test

import (
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/AtomiCloud/diene.boron/lib/operator/boron"
)

var kirinCoordinates = boron.Coordinates{
	Landscape: "lapras", Platform: "nitroso", Service: "oxygen", Module: "viewer",
}

func TestHostnameCanonicalDottedForm(t *testing.T) {
	got := boron.Hostname(kirinCoordinates, "kirin", "admin.atomi.cloud")
	require.Equal(t, "viewer.oxygen.nitroso.kirin.lapras.admin.atomi.cloud", got)
}

func TestHostnameNormalizesCaseAndDots(t *testing.T) {
	got := boron.Hostname(boron.Coordinates{
		Landscape: "Lapras", Platform: "NITROSO", Service: "oxygen.", Module: ".Viewer",
	}, "Kirin", "Admin.Atomi.Cloud.")
	require.Equal(t, "viewer.oxygen.nitroso.kirin.lapras.admin.atomi.cloud", got)
}

func TestNormalizePathDefaultsToWildcard(t *testing.T) {
	require.Equal(t, "/*", boron.NormalizePath(""))
	require.Equal(t, "/api/*", boron.NormalizePath("/api/*"))
}

func TestValidPathSegmentBoundaryRules(t *testing.T) {
	for path, valid := range map[string]bool{
		"/*":        true,
		"/":         true,
		"/api/*":    true,
		"/api/v1/*": true,
		"/api":      true,
		"api/*":     false, // must start with /
		"/api*":     false, // partial-segment wildcard
		"/a?b=c":    false, // query string
		"/a#frag":   false, // fragment
		"/a:8080":   false, // port
	} {
		require.Equal(t, valid, boron.ValidPath(path), "path %q", path)
	}
}

func TestAdmitProfileConnectedLapras(t *testing.T) {
	admitted := boron.AdmitProfile(boron.InstallationIdentity{Profile: boron.ProfileLapras, Connected: true})
	require.True(t, admitted.Allowed)

	refused := boron.AdmitProfile(boron.InstallationIdentity{Profile: boron.ProfileLapras})
	require.False(t, refused.Allowed)
	require.Equal(t, boron.ReasonProfileUnsupported, refused.Reason)
}

func TestAdmitProfileDittoNeedsExplicitEnable(t *testing.T) {
	require.True(t, boron.AdmitProfile(boron.InstallationIdentity{Profile: boron.ProfileDitto, Connected: true, DittoEnabled: true}).Allowed)
	require.False(t, boron.AdmitProfile(boron.InstallationIdentity{Profile: boron.ProfileDitto, Connected: true}).Allowed)
	require.False(t, boron.AdmitProfile(boron.InstallationIdentity{Profile: boron.ProfileDitto, DittoEnabled: true}).Allowed)
}

func TestAdmitProfileRegisteredAlwaysAllowed(t *testing.T) {
	require.True(t, boron.AdmitProfile(boron.InstallationIdentity{Profile: boron.ProfileRegistered}).Allowed)
}

func TestAdmitProfileHostedAndHermeticNeverRun(t *testing.T) {
	for _, profile := range []string{"eevee", "plusle", "minun", "rotom", "absol", ""} {
		admission := boron.AdmitProfile(boron.InstallationIdentity{Profile: profile, Connected: true, DittoEnabled: true})
		require.False(t, admission.Allowed, "profile %q must be refused", profile)
		require.Equal(t, boron.ReasonProfileUnsupported, admission.Reason)
	}
}

func TestBackendURL(t *testing.T) {
	require.Equal(t, "http://viewer.nitroso.svc.cluster.local:8080", boron.BackendURL("nitroso", "viewer", 8080))
}

func TestSharedBackendAllowed(t *testing.T) {
	require.True(t, boron.SharedBackendAllowed(false, false), "private backend needs no opt-in")
	require.True(t, boron.SharedBackendAllowed(true, true), "public backend with opt-in allowed")
	require.False(t, boron.SharedBackendAllowed(true, false), "public backend without opt-in denied")
}

func TestOlderByCreationTime(t *testing.T) {
	early := boron.ConflictCandidate{Namespace: "a", Name: "x", CreatedAt: time.Unix(100, 0)}
	late := boron.ConflictCandidate{Namespace: "a", Name: "y", CreatedAt: time.Unix(200, 0)}
	require.True(t, boron.Older(early, late))
	require.False(t, boron.Older(late, early))
}

func TestOlderTieBreaksOnNamespaceName(t *testing.T) {
	at := time.Unix(100, 0)
	left := boron.ConflictCandidate{Namespace: "a", Name: "x", CreatedAt: at}
	right := boron.ConflictCandidate{Namespace: "b", Name: "x", CreatedAt: at}
	require.True(t, boron.Older(left, right))
	require.False(t, boron.Older(right, left))
}
