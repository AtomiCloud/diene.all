package operator_test

import (
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/AtomiCloud/diene.boron/lib/operator/reconcile"
)

func findCondition(conditions []reconcile.Condition, conditionType string) *reconcile.Condition {
	for i := range conditions {
		if conditions[i].Type == conditionType {
			return &conditions[i]
		}
	}
	return nil
}

func requireDecided(t *testing.T, conditions []reconcile.Condition, conditionType, status, reason string) {
	t.Helper()
	condition := findCondition(conditions, conditionType)
	require.NotNil(t, condition, "condition %s missing", conditionType)
	require.Equal(t, status, condition.Status, "condition %s status", conditionType)
	if reason != "" {
		require.Equal(t, reason, condition.Reason, "condition %s reason", conditionType)
	}
}

// ─── DecideAccount ───────────────────────────────────────────────────────────

func TestDecideAccountValid(t *testing.T) {
	decision := reconcile.DecideAccount(reconcile.AccountInput{
		SecretFound: true, TokenPresent: true, Checked: true, ProviderReachable: true, TokenValid: true,
	})
	require.True(t, decision.Ready)
	requireDecided(t, decision.Conditions, reconcile.TypeTokenValid, reconcile.StatusTrue, "TokenValidated")
	requireDecided(t, decision.Conditions, reconcile.TypeReady, reconcile.StatusTrue, "AccountReady")
	require.Len(t, decision.Events, 1)
	require.Equal(t, reconcile.EventNormal, decision.Events[0].Type)
}

func TestDecideAccountSecretMissing(t *testing.T) {
	decision := reconcile.DecideAccount(reconcile.AccountInput{})
	require.False(t, decision.Ready)
	requireDecided(t, decision.Conditions, reconcile.TypeTokenValid, reconcile.StatusFalse, "SecretMissing")
	requireDecided(t, decision.Conditions, reconcile.TypeReady, reconcile.StatusFalse, "SecretMissing")
}

func TestDecideAccountTokenKeyMissing(t *testing.T) {
	decision := reconcile.DecideAccount(reconcile.AccountInput{SecretFound: true})
	requireDecided(t, decision.Conditions, reconcile.TypeReady, reconcile.StatusFalse, "SecretMissing")
}

func TestDecideAccountProviderUnreachable(t *testing.T) {
	withMessage := reconcile.DecideAccount(reconcile.AccountInput{
		SecretFound: true, TokenPresent: true, Checked: true, ProviderMessage: "dial tcp: timeout",
	})
	requireDecided(t, withMessage.Conditions, reconcile.TypeReady, reconcile.StatusFalse, "ProviderUnreachable")
	require.Equal(t, "dial tcp: timeout", findCondition(withMessage.Conditions, reconcile.TypeReady).Message)

	unchecked := reconcile.DecideAccount(reconcile.AccountInput{SecretFound: true, TokenPresent: true})
	requireDecided(t, unchecked.Conditions, reconcile.TypeReady, reconcile.StatusFalse, "ProviderUnreachable")
	require.Equal(t, "cloudflare api unreachable", findCondition(unchecked.Conditions, reconcile.TypeReady).Message)
}

func TestDecideAccountTokenInvalid(t *testing.T) {
	decision := reconcile.DecideAccount(reconcile.AccountInput{
		SecretFound: true, TokenPresent: true, Checked: true, ProviderReachable: true, TokenValid: false,
	})
	requireDecided(t, decision.Conditions, reconcile.TypeTokenValid, reconcile.StatusFalse, "TokenInvalid")
	requireDecided(t, decision.Conditions, reconcile.TypeReady, reconcile.StatusFalse, "TokenInvalid")
	require.Len(t, decision.Events, 1)
	require.Equal(t, reconcile.EventWarning, decision.Events[0].Type)
}

// ─── DecideTunnel ────────────────────────────────────────────────────────────

func TestDecideTunnelHealthy(t *testing.T) {
	decision := reconcile.DecideTunnel(reconcile.TunnelInput{
		AccountFound: true, AccountReady: true, TunnelEnsured: true, ConfigPushed: true,
		AvailableReplicas: reconcile.TunnelReplicas,
	})
	requireDecided(t, decision.Conditions, reconcile.TypeAccountNotReady, reconcile.StatusFalse, "AccountReady")
	requireDecided(t, decision.Conditions, reconcile.TypeConfigSynced, reconcile.StatusTrue, "ConfigSynced")
	requireDecided(t, decision.Conditions, reconcile.TypeReplicasReady, reconcile.StatusTrue, "ReplicasReady")
	require.Empty(t, decision.Events)
}

func TestDecideTunnelAccountMissing(t *testing.T) {
	decision := reconcile.DecideTunnel(reconcile.TunnelInput{})
	requireDecided(t, decision.Conditions, reconcile.TypeAccountNotReady, reconcile.StatusTrue, "AccountNotReady")
	require.Equal(t, "referenced Account not found", findCondition(decision.Conditions, reconcile.TypeAccountNotReady).Message)
	requireDecided(t, decision.Conditions, reconcile.TypeConfigSynced, reconcile.StatusFalse, "AccountNotReady")
}

func TestDecideTunnelAccountNotReady(t *testing.T) {
	decision := reconcile.DecideTunnel(reconcile.TunnelInput{AccountFound: true})
	requireDecided(t, decision.Conditions, reconcile.TypeAccountNotReady, reconcile.StatusTrue, "AccountNotReady")
	require.Equal(t, "referenced Account is not ready", findCondition(decision.Conditions, reconcile.TypeAccountNotReady).Message)
}

func TestDecideTunnelConfigPushFailedReddens(t *testing.T) {
	decision := reconcile.DecideTunnel(reconcile.TunnelInput{
		AccountFound: true, AccountReady: true, TunnelEnsured: true, ConfigPushed: false,
		ProviderMessage: "push failed", AvailableReplicas: 1,
	})
	requireDecided(t, decision.Conditions, reconcile.TypeConfigSynced, reconcile.StatusFalse, "ConfigPushFailed")
	require.Equal(t, "push failed", findCondition(decision.Conditions, reconcile.TypeConfigSynced).Message)
	requireDecided(t, decision.Conditions, reconcile.TypeReplicasReady, reconcile.StatusFalse, "ReplicasPending")
	require.Contains(t, findCondition(decision.Conditions, reconcile.TypeReplicasReady).Message, "1/2")
	require.Len(t, decision.Events, 1)
}

func TestDecideTunnelEnsureFailedDefaultMessage(t *testing.T) {
	decision := reconcile.DecideTunnel(reconcile.TunnelInput{AccountFound: true, AccountReady: true})
	requireDecided(t, decision.Conditions, reconcile.TypeConfigSynced, reconcile.StatusFalse, "ConfigPushFailed")
	require.Equal(t, "remote tunnel configuration push failed", findCondition(decision.Conditions, reconcile.TypeConfigSynced).Message)
}

// ─── DecideExposure ──────────────────────────────────────────────────────────

func connectedInstallation() reconcile.Installation {
	return reconcile.Installation{
		Profile: reconcile.ProfileLapras, Connected: true, Landscape: "lapras", Instance: "kirin",
	}
}

func healthyExposureInput() reconcile.ExposureInput {
	return reconcile.ExposureInput{
		Installation: connectedInstallation(),
		Coordinates:  reconcile.Coordinates{Landscape: "lapras", Platform: "nitroso", Service: "oxygen", Module: "viewer"},
		Instance:     "kirin",
		Namespace:    "nitroso",
		TunnelFound:  true,
		TunnelZone:   "admin.atomi.cloud",
		AccountFound: true, AccountReady: true,
		BackendFound: true, BackendPortFound: true,
		BackendName: "viewer", BackendPort: 8080,
		TLSChecked: true, TLSCovered: true,
		PolicyNames:    []string{"atomi-admins", "atomi-data-owners"},
		ResolvedPolicy: map[string]string{"atomi-admins": "p1", "atomi-data-owners": "p2"},
		Self:           reconcile.ConflictCandidate{Namespace: "nitroso", Name: "viewer", CreatedAt: time.Unix(100, 0)},
	}
}

func TestDecideExposureProgramsInPolicyOrder(t *testing.T) {
	decision := reconcile.DecideExposure(healthyExposureInput())
	require.NotNil(t, decision.Program)
	require.Equal(t, "viewer.oxygen.nitroso.kirin.lapras.admin.atomi.cloud", decision.Program.Hostname)
	require.Equal(t, "/*", decision.Program.Path)
	require.Equal(t, "http://viewer.nitroso.svc.cluster.local:8080", decision.Program.Backend)
	require.Equal(t, []string{"p1", "p2"}, decision.Program.PolicyIDs, "array order IS CF evaluation order")
	requireDecided(t, decision.Conditions, reconcile.TypeAccepted, reconcile.StatusTrue, "Accepted")
	requireDecided(t, decision.Conditions, reconcile.TypeResolvedRefs, reconcile.StatusTrue, "ResolvedRefs")
	requireDecided(t, decision.Conditions, reconcile.TypeConflicted, reconcile.StatusFalse, "NoConflict")
}

func TestDecideExposureProfileRefused(t *testing.T) {
	in := healthyExposureInput()
	in.Installation.Profile = "eevee"
	decision := reconcile.DecideExposure(in)
	require.Nil(t, decision.Program)
	requireDecided(t, decision.Conditions, reconcile.TypeAccepted, reconcile.StatusFalse, "ProfileUnsupported")
	requireDecided(t, decision.Conditions, reconcile.TypeProgrammed, reconcile.StatusFalse, "ProfileUnsupported")
}

func TestDecideExposureTunnelMissing(t *testing.T) {
	in := healthyExposureInput()
	in.TunnelFound = false
	decision := reconcile.DecideExposure(in)
	require.Nil(t, decision.Program)
	requireDecided(t, decision.Conditions, reconcile.TypeAccepted, reconcile.StatusFalse, "TunnelMissing")
}

func TestDecideExposureAccountNotReady(t *testing.T) {
	in := healthyExposureInput()
	in.AccountReady = false
	decision := reconcile.DecideExposure(in)
	require.Nil(t, decision.Program)
	requireDecided(t, decision.Conditions, reconcile.TypeAccepted, reconcile.StatusFalse, "AccountNotReady")
}

func TestDecideExposurePlatformNamespaceMismatch(t *testing.T) {
	in := healthyExposureInput()
	in.Namespace = "elsewhere"
	decision := reconcile.DecideExposure(in)
	require.Nil(t, decision.Program)
	requireDecided(t, decision.Conditions, reconcile.TypeAccepted, reconcile.StatusFalse, "CoordinatesMismatch")
}

func TestDecideExposureUntrustedLandscapeOrInstance(t *testing.T) {
	byLandscape := healthyExposureInput()
	byLandscape.Coordinates.Landscape = "raichu"
	require.Nil(t, reconcile.DecideExposure(byLandscape).Program)

	byInstance := healthyExposureInput()
	byInstance.Instance = "someone-else"
	decision := reconcile.DecideExposure(byInstance)
	require.Nil(t, decision.Program)
	requireDecided(t, decision.Conditions, reconcile.TypeAccepted, reconcile.StatusFalse, "CoordinatesMismatch")
}

func TestDecideExposureRegisteredSkipsProfileMetadataMatch(t *testing.T) {
	in := healthyExposureInput()
	in.Installation = reconcile.Installation{Profile: reconcile.ProfileRegistered}
	in.Coordinates.Landscape = "raichu"
	in.Instance = "raichu-a"
	decision := reconcile.DecideExposure(in)
	require.NotNil(t, decision.Program, "registered clusters use their stable cluster mark")
	require.Equal(t, "viewer.oxygen.nitroso.raichu-a.raichu.admin.atomi.cloud", decision.Program.Hostname)
}

func TestDecideExposureUnsupportedMatchRefused(t *testing.T) {
	in := healthyExposureInput()
	in.Path = "/api*"
	decision := reconcile.DecideExposure(in)
	require.Nil(t, decision.Program)
	requireDecided(t, decision.Conditions, reconcile.TypeAccepted, reconcile.StatusFalse, "UnsupportedMatch")
}

func TestDecideExposureTLSFailsClosed(t *testing.T) {
	uncovered := healthyExposureInput()
	uncovered.TLSCovered = false
	uncovered.TLSMessage = "no exact cert"
	decision := reconcile.DecideExposure(uncovered)
	require.Nil(t, decision.Program, "no DNS, Access Application, or ingress rule may be programmed")
	requireDecided(t, decision.Conditions, reconcile.TypeAccepted, reconcile.StatusFalse, "UnsupportedTLSCoverage")
	require.Equal(t, "no exact cert", findCondition(decision.Conditions, reconcile.TypeAccepted).Message)
	require.NotEmpty(t, decision.Hostname, "the derived hostname still surfaces for diagnostics")

	unchecked := healthyExposureInput()
	unchecked.TLSChecked = false
	unchecked.TLSMessage = ""
	fallback := reconcile.DecideExposure(unchecked)
	require.Nil(t, fallback.Program)
	require.Contains(t, findCondition(fallback.Conditions, reconcile.TypeAccepted).Message, "cannot prove exact DNS/edge-TLS coverage")
}

func TestDecideExposureBackendRefusals(t *testing.T) {
	missing := healthyExposureInput()
	missing.BackendFound = false
	decision := reconcile.DecideExposure(missing)
	require.Nil(t, decision.Program)
	requireDecided(t, decision.Conditions, reconcile.TypeResolvedRefs, reconcile.StatusFalse, "BackendNotFound")
	require.Equal(t, "backend Service not found", findCondition(decision.Conditions, reconcile.TypeResolvedRefs).Message)

	noPort := healthyExposureInput()
	noPort.BackendPortFound = false
	decision = reconcile.DecideExposure(noPort)
	require.Nil(t, decision.Program)
	require.Equal(t, "backend Service does not expose the named port", findCondition(decision.Conditions, reconcile.TypeResolvedRefs).Message)
}

func TestDecideExposureSharedBackendGuardrail(t *testing.T) {
	denied := healthyExposureInput()
	denied.BackendPublic = true
	decision := reconcile.DecideExposure(denied)
	require.Nil(t, decision.Program)
	requireDecided(t, decision.Conditions, reconcile.TypeResolvedRefs, reconcile.StatusFalse, "SharedBackendDenied")

	allowed := healthyExposureInput()
	allowed.BackendPublic = true
	allowed.AllowSharedBackend = true
	require.NotNil(t, reconcile.DecideExposure(allowed).Program)
}

func TestDecideExposureAnyMissingPolicyProgramsNothing(t *testing.T) {
	in := healthyExposureInput()
	delete(in.ResolvedPolicy, "atomi-data-owners")
	decision := reconcile.DecideExposure(in)
	require.Nil(t, decision.Program, "no partial route, no subset attach")
	requireDecided(t, decision.Conditions, reconcile.TypeResolvedRefs, reconcile.StatusFalse, "PolicyMissing")
	require.Contains(t, findCondition(decision.Conditions, reconcile.TypeResolvedRefs).Message, "atomi-data-owners")

	emptyID := healthyExposureInput()
	emptyID.ResolvedPolicy["atomi-admins"] = ""
	require.Nil(t, reconcile.DecideExposure(emptyID).Program, "an empty id is a missing policy")
}

func TestDecideExposureOldestWins(t *testing.T) {
	loser := healthyExposureInput()
	loser.HasRival = true
	loser.Oldest = reconcile.ConflictCandidate{Namespace: "nitroso", Name: "older", CreatedAt: time.Unix(50, 0)}
	decision := reconcile.DecideExposure(loser)
	require.Nil(t, decision.Program)
	requireDecided(t, decision.Conditions, reconcile.TypeConflicted, reconcile.StatusTrue, "HostnameConflict")
	requireDecided(t, decision.Conditions, reconcile.TypeProgrammed, reconcile.StatusFalse, "HostnameConflict")

	winner := healthyExposureInput()
	winner.HasRival = true
	winner.Oldest = reconcile.ConflictCandidate{Namespace: "nitroso", Name: "newer", CreatedAt: time.Unix(500, 0)}
	require.NotNil(t, reconcile.DecideExposure(winner).Program, "the older CR keeps winning")
}

func TestProgrammedCondition(t *testing.T) {
	ok := reconcile.ProgrammedLive()
	require.Equal(t, reconcile.StatusTrue, ok.Status)
	require.Equal(t, "Programmed", ok.Reason)

	failed := reconcile.ProgrammedPending("dns write failed")
	require.Equal(t, reconcile.StatusFalse, failed.Status)
	require.Equal(t, "ProgrammingPending", failed.Reason)
	require.Equal(t, "dns write failed", failed.Message)
}

func TestReExportedHelpers(t *testing.T) {
	require.Equal(t, "viewer.oxygen.nitroso.kirin.lapras.zone.example",
		reconcile.DeriveHostname(reconcile.Coordinates{Landscape: "lapras", Platform: "nitroso", Service: "oxygen", Module: "viewer"}, "kirin", "zone.example"))
	require.Equal(t, "/*", reconcile.NormalizePath(""))
	require.True(t, reconcile.OlderCandidate(
		reconcile.ConflictCandidate{Namespace: "a", Name: "x", CreatedAt: time.Unix(1, 0)},
		reconcile.ConflictCandidate{Namespace: "a", Name: "y", CreatedAt: time.Unix(2, 0)},
	))
}
