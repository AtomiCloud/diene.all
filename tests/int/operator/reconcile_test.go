package operator_test

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	apimeta "k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/tools/record"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"

	"github.com/AtomiCloud/diene.boron/adapters/operator/cloudflare"
	"github.com/AtomiCloud/diene.boron/adapters/operator/controllers"
	"github.com/AtomiCloud/diene.boron/adapters/operator/kube"
	"github.com/AtomiCloud/diene.boron/adapters/operator/metrics"
	apiv1alpha1 "github.com/AtomiCloud/diene.boron/api/v1alpha1"
	"github.com/AtomiCloud/diene.boron/lib/operator/reconcile"
)

type fakeClock struct{ t time.Time }

func (c fakeClock) Now() time.Time { return c.t }

// fixture bundles the three reconcilers over one fake provider and one namespace.
type fixture struct {
	namespace string
	fake      *cloudflare.Memory
	account   *controllers.AccountReconciler
	tunnel    *controllers.TunnelReconciler
	exposure  *controllers.ExposureReconciler
}

var namespaceSequence int

func connectedLapras(t *testing.T) *fixture {
	t.Helper()
	return newFixture(t, reconcile.Installation{
		Profile: reconcile.ProfileLapras, Connected: true, Landscape: "lapras", Instance: "kirin",
	})
}

func newFixture(t *testing.T, installation reconcile.Installation) *fixture {
	t.Helper()
	namespaceSequence++
	namespace := fmt.Sprintf("nitroso%d", namespaceSequence)
	require.NoError(t, k8sClient.Create(context.Background(), &corev1.Namespace{
		ObjectMeta: metav1.ObjectMeta{Name: namespace},
	}))

	fake := cloudflare.NewMemory()
	fake.Policies["atomi-admins"] = "policy-1"
	fake.Policies["atomi-data-owners"] = "policy-2"

	clock := fakeClock{t: time.Unix(1700000000, 0).UTC()}
	recorder := kube.NewEventRecorder(record.NewFakeRecorder(256))
	prometheus := metrics.NewPrometheus()
	secrets := kube.NewSecretAdapter(k8sClient)

	return &fixture{
		namespace: namespace,
		fake:      fake,
		account: &controllers.AccountReconciler{
			Client: k8sClient, Clock: clock, Recorder: recorder,
			Secrets: secrets, Provider: fake, Metrics: prometheus,
		},
		tunnel: &controllers.TunnelReconciler{
			Client: k8sClient, Clock: clock, Recorder: recorder,
			Secrets:     secrets,
			Deployments: kube.NewDeploymentAdapter(k8sClient, testScheme, controllers.TunnelOwnerLabel),
			Provider:    fake, Metrics: prometheus,
			CloudflaredImage: "cloudflare/cloudflared:2025.7.0",
		},
		exposure: &controllers.ExposureReconciler{
			Client: k8sClient, Clock: clock, Recorder: recorder,
			Secrets: secrets, Services: kube.NewServiceAdapter(k8sClient),
			Provider: fake, Metrics: prometheus,
			Installation: installation,
		},
	}
}

func (f *fixture) createSecret(t *testing.T, name, token string) {
	t.Helper()
	require.NoError(t, k8sClient.Create(context.Background(), &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: f.namespace},
		Data:       map[string][]byte{"token": []byte(token)},
	}))
}

func (f *fixture) createService(t *testing.T, name string, port int32, public bool) { //nolint:revive // fixture helper; the flag mirrors the annotation under test
	t.Helper()
	service := &corev1.Service{
		ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: f.namespace},
		Spec:       corev1.ServiceSpec{Ports: []corev1.ServicePort{{Port: port}}},
	}
	if public {
		service.Annotations = map[string]string{controllers.PublicServiceAnnotation: "true"}
	}
	require.NoError(t, k8sClient.Create(context.Background(), service))
}

func (f *fixture) createAccount(t *testing.T, name, secretName string) *apiv1alpha1.Account {
	t.Helper()
	account := &apiv1alpha1.Account{
		ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: f.namespace},
		Spec: apiv1alpha1.AccountSpec{
			AccountID:         "acc-" + f.namespace,
			APITokenSecretRef: apiv1alpha1.SecretNameReference{Name: secretName},
		},
	}
	require.NoError(t, k8sClient.Create(context.Background(), account))
	return account
}

func (f *fixture) createTunnel(t *testing.T, name, accountName, zone string) *apiv1alpha1.Tunnel {
	t.Helper()
	tunnel := &apiv1alpha1.Tunnel{
		ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: f.namespace},
		Spec: apiv1alpha1.TunnelSpec{
			AccountRef: apiv1alpha1.SecretNameReference{Name: accountName},
			Zone:       zone,
		},
	}
	require.NoError(t, k8sClient.Create(context.Background(), tunnel))
	return tunnel
}

type exposureOptions struct {
	name     string
	module   string
	backend  string
	policies []string
	path     string
	shared   bool
	instance string
}

func (f *fixture) createExposure(t *testing.T, opts exposureOptions) *apiv1alpha1.Exposure {
	t.Helper()
	if opts.policies == nil {
		opts.policies = []string{"atomi-admins"}
	}
	if opts.instance == "" {
		opts.instance = "kirin"
	}
	exposure := &apiv1alpha1.Exposure{
		ObjectMeta: metav1.ObjectMeta{Name: opts.name, Namespace: f.namespace},
		Spec: apiv1alpha1.ExposureSpec{
			TunnelRef: apiv1alpha1.SecretNameReference{Name: "admin"},
			Coordinates: apiv1alpha1.Coordinates{
				Landscape: "lapras", Platform: f.namespace, Service: "oxygen", Module: opts.module,
			},
			Instance:           opts.instance,
			Path:               opts.path,
			Backend:            apiv1alpha1.BackendReference{Name: opts.backend, Port: 8080},
			Policies:           opts.policies,
			AllowSharedBackend: opts.shared,
		},
	}
	require.NoError(t, k8sClient.Create(context.Background(), exposure))
	return exposure
}

func reconcileAccount(t *testing.T, f *fixture, name string, times int) {
	t.Helper()
	key := client.ObjectKey{Namespace: f.namespace, Name: name}
	for range times {
		_, err := f.account.Reconcile(context.Background(), ctrl.Request{NamespacedName: key})
		require.NoError(t, err)
	}
}

func reconcileTunnel(t *testing.T, f *fixture, name string, times int) {
	t.Helper()
	key := client.ObjectKey{Namespace: f.namespace, Name: name}
	for range times {
		_, err := f.tunnel.Reconcile(context.Background(), ctrl.Request{NamespacedName: key})
		require.NoError(t, err)
	}
}

func reconcileExposure(t *testing.T, f *fixture, name string, times int) {
	t.Helper()
	key := client.ObjectKey{Namespace: f.namespace, Name: name}
	for range times {
		_, err := f.exposure.Reconcile(context.Background(), ctrl.Request{NamespacedName: key})
		require.NoError(t, err)
	}
}

func getAccount(t *testing.T, f *fixture, name string) *apiv1alpha1.Account {
	t.Helper()
	var account apiv1alpha1.Account
	require.NoError(t, k8sClient.Get(context.Background(), client.ObjectKey{Namespace: f.namespace, Name: name}, &account))
	return &account
}

func getTunnel(t *testing.T, f *fixture, name string) *apiv1alpha1.Tunnel {
	t.Helper()
	var tunnel apiv1alpha1.Tunnel
	require.NoError(t, k8sClient.Get(context.Background(), client.ObjectKey{Namespace: f.namespace, Name: name}, &tunnel))
	return &tunnel
}

func getExposure(t *testing.T, f *fixture, name string) *apiv1alpha1.Exposure {
	t.Helper()
	var exposure apiv1alpha1.Exposure
	require.NoError(t, k8sClient.Get(context.Background(), client.ObjectKey{Namespace: f.namespace, Name: name}, &exposure))
	return &exposure
}

func requireCondition(t *testing.T, conditions []metav1.Condition, conditionType string, status metav1.ConditionStatus, reason string) {
	t.Helper()
	condition := apimeta.FindStatusCondition(conditions, conditionType)
	require.NotNil(t, condition, "condition %s missing", conditionType)
	require.Equal(t, status, condition.Status, "condition %s status (reason %s: %s)", conditionType, condition.Reason, condition.Message)
	if reason != "" {
		require.Equal(t, reason, condition.Reason, "condition %s reason", conditionType)
	}
}

// convergedChain creates and reconciles a Ready Account and a synced Tunnel.
func convergedChain(t *testing.T, f *fixture) {
	t.Helper()
	f.createSecret(t, "cf-edge-token", "good-token")
	f.createAccount(t, "main", "cf-edge-token")
	reconcileAccount(t, f, "main", 1)
	f.createTunnel(t, "admin", "main", "admin.atomi.cloud")
	reconcileTunnel(t, f, "admin", 2)
}

// ─── Account (DoD: token once + AccountNotReady propagation) ────────────────

func TestAccountValidatesTokenOnceAndSetsReady(t *testing.T) {
	f := connectedLapras(t)
	f.createSecret(t, "cf-edge-token", "good-token")
	f.createAccount(t, "main", "cf-edge-token")
	reconcileAccount(t, f, "main", 2)

	account := getAccount(t, f, "main")
	requireCondition(t, account.Status.Conditions, reconcile.TypeTokenValid, metav1.ConditionTrue, "TokenValidated")
	requireCondition(t, account.Status.Conditions, reconcile.TypeReady, metav1.ConditionTrue, "AccountReady")
	require.Equal(t, account.Generation, account.Status.ObservedGeneration)
}

func TestAccountInvalidTokenPropagatesWithoutPerDependentCalls(t *testing.T) {
	f := connectedLapras(t)
	f.createSecret(t, "cf-edge-token", "bad-token")
	f.fake.InvalidTokens["bad-token"] = true
	f.createAccount(t, "main", "cf-edge-token")
	reconcileAccount(t, f, "main", 1)

	account := getAccount(t, f, "main")
	requireCondition(t, account.Status.Conditions, reconcile.TypeTokenValid, metav1.ConditionFalse, "TokenInvalid")
	requireCondition(t, account.Status.Conditions, reconcile.TypeReady, metav1.ConditionFalse, "TokenInvalid")

	// Dependent Tunnel and Exposure surface AccountNotReady from the Account's
	// status alone: the failed Account produces no extra provider API calls.
	f.createTunnel(t, "admin", "main", "admin.atomi.cloud")
	reconcileTunnel(t, f, "admin", 2)
	tunnel := getTunnel(t, f, "admin")
	requireCondition(t, tunnel.Status.Conditions, reconcile.TypeAccountNotReady, metav1.ConditionTrue, "AccountNotReady")

	f.createService(t, "viewer", 8080, false)
	f.createExposure(t, exposureOptions{name: "viewer", module: "viewer", backend: "viewer"})
	reconcileExposure(t, f, "viewer", 2)
	exposure := getExposure(t, f, "viewer")
	requireCondition(t, exposure.Status.Conditions, reconcile.TypeAccepted, metav1.ConditionFalse, "AccountNotReady")

	require.Zero(t, f.fake.WriteCount(), "a dead token must produce zero provider writes")
}

func TestAccountMissingSecretRefused(t *testing.T) {
	f := connectedLapras(t)
	f.createAccount(t, "main", "absent-secret")
	reconcileAccount(t, f, "main", 1)

	account := getAccount(t, f, "main")
	requireCondition(t, account.Status.Conditions, reconcile.TypeReady, metav1.ConditionFalse, "SecretMissing")
}

// ─── Tunnel (DoD: 2 replicas, remote config, hot-reload, redden) ─────────────

func TestTunnelConvergesWithFixedReplicasAndRemoteConfig(t *testing.T) {
	f := connectedLapras(t)
	convergedChain(t, f)

	tunnel := getTunnel(t, f, "admin")
	requireCondition(t, tunnel.Status.Conditions, reconcile.TypeAccountNotReady, metav1.ConditionFalse, "AccountReady")
	requireCondition(t, tunnel.Status.Conditions, reconcile.TypeConfigSynced, metav1.ConditionTrue, "ConfigSynced")
	require.NotEmpty(t, tunnel.Status.TunnelID)

	var deployment appsv1.Deployment
	require.NoError(t, k8sClient.Get(context.Background(),
		client.ObjectKey{Namespace: f.namespace, Name: "cloudflared-admin"}, &deployment))
	require.NotNil(t, deployment.Spec.Replicas)
	require.Equal(t, reconcile.TunnelReplicas, *deployment.Spec.Replicas)

	// The CRD carries no replica field at all — fixed 2, no HPA lever.
	requireCondition(t, tunnel.Status.Conditions, reconcile.TypeReplicasReady, metav1.ConditionFalse, "ReplicasPending")
}

func TestTunnelRemoteConfigHotReloadsWithoutRestart(t *testing.T) {
	f := connectedLapras(t)
	convergedChain(t, f)
	f.createService(t, "viewer", 8080, false)
	f.createExposure(t, exposureOptions{name: "viewer", module: "viewer", backend: "viewer"})
	reconcileExposure(t, f, "viewer", 2)
	reconcileTunnel(t, f, "admin", 2)

	tunnel := getTunnel(t, f, "admin")
	configKey := "acc-" + f.namespace + "/" + tunnel.Status.TunnelID
	require.NotEmpty(t, f.fake.Configs[configKey], "exposure rule must reach the remote config")
	pushesBefore := f.fake.ConfigPushes[configKey]

	// Deployment generation must not change across a config re-push: the new
	// rule set arrives via the API-pushed remote config, not a pod restart.
	var deploymentBefore appsv1.Deployment
	require.NoError(t, k8sClient.Get(context.Background(),
		client.ObjectKey{Namespace: f.namespace, Name: "cloudflared-admin"}, &deploymentBefore))

	f.createExposure(t, exposureOptions{name: "viewer2", module: "editor", backend: "viewer"})
	reconcileExposure(t, f, "viewer2", 2)
	reconcileTunnel(t, f, "admin", 2)

	require.Greater(t, f.fake.ConfigPushes[configKey], pushesBefore, "second exposure must re-push the remote config")
	require.Len(t, f.fake.Configs[configKey], 2)

	var deploymentAfter appsv1.Deployment
	require.NoError(t, k8sClient.Get(context.Background(),
		client.ObjectKey{Namespace: f.namespace, Name: "cloudflared-admin"}, &deploymentAfter))
	require.Equal(t, deploymentBefore.Generation, deploymentAfter.Generation,
		"config hot-reload must not roll the cloudflared Deployment")
}

func TestTunnelBrokenConfigPushReddensConfigSyncedOnly(t *testing.T) {
	f := connectedLapras(t)
	convergedChain(t, f)

	f.fake.FailConfigPush = true
	reconcileTunnel(t, f, "admin", 2)

	tunnel := getTunnel(t, f, "admin")
	requireCondition(t, tunnel.Status.Conditions, reconcile.TypeConfigSynced, metav1.ConditionFalse, "ConfigPushFailed")

	// Replicas stay untouched while the config push fails.
	var deployment appsv1.Deployment
	require.NoError(t, k8sClient.Get(context.Background(),
		client.ObjectKey{Namespace: f.namespace, Name: "cloudflared-admin"}, &deployment))
	require.Equal(t, reconcile.TunnelReplicas, *deployment.Spec.Replicas)

	f.fake.FailConfigPush = false
	reconcileTunnel(t, f, "admin", 2)
	tunnel = getTunnel(t, f, "admin")
	requireCondition(t, tunnel.Status.Conditions, reconcile.TypeConfigSynced, metav1.ConditionTrue, "ConfigSynced")
}

// ─── Exposure (DoD: derivation, ordered policies, DNS + ingress) ─────────────

func TestExposureDerivesHostnameAndProgramsInOrder(t *testing.T) {
	f := connectedLapras(t)
	convergedChain(t, f)
	f.createService(t, "viewer", 8080, false)
	f.createExposure(t, exposureOptions{
		name: "viewer", module: "viewer", backend: "viewer",
		policies: []string{"atomi-admins", "atomi-data-owners"},
	})
	reconcileExposure(t, f, "viewer", 2)

	exposure := getExposure(t, f, "viewer")
	hostname := "viewer.oxygen." + f.namespace + ".kirin.lapras.admin.atomi.cloud"
	require.Equal(t, hostname, exposure.Status.Hostname)
	requireCondition(t, exposure.Status.Conditions, reconcile.TypeAccepted, metav1.ConditionTrue, "Accepted")
	requireCondition(t, exposure.Status.Conditions, reconcile.TypeResolvedRefs, metav1.ConditionTrue, "ResolvedRefs")
	requireCondition(t, exposure.Status.Conditions, reconcile.TypeProgrammed, metav1.ConditionTrue, "Programmed")
	requireCondition(t, exposure.Status.Conditions, reconcile.TypeConflicted, metav1.ConditionFalse, "NoConflict")

	// Access Application carries the policies in the exact array order
	// (CF-native evaluation order), and the DNS CNAME points at the tunnel.
	appKey := "acc-" + f.namespace + "/" + hostname + "/*"
	app, ok := f.fake.Applications[appKey]
	require.True(t, ok, "access application must exist")
	require.Equal(t, []string{"policy-1", "policy-2"}, app.PolicyIDs)

	tunnel := getTunnel(t, f, "admin")
	target := f.fake.DNS["acc-"+f.namespace+"/admin.atomi.cloud/"+hostname]
	require.Equal(t, tunnel.Status.TunnelID+".cfargotunnel.com", target)

	// The programmed rule feeds the tunnel's remote config.
	require.Equal(t, hostname, exposure.Status.ProgrammedRule.Hostname)
	require.Equal(t, "http://viewer."+f.namespace+".svc.cluster.local:8080", exposure.Status.ProgrammedRule.Backend)
}

func TestExposureUnsupportedTLSCoverageFailsClosed(t *testing.T) {
	f := connectedLapras(t)
	convergedChain(t, f)
	f.createService(t, "viewer", 8080, false)

	writesBefore := f.fake.WriteCount()
	f.fake.UncoveredZones["admin.atomi.cloud"] = true
	f.createExposure(t, exposureOptions{name: "viewer", module: "viewer", backend: "viewer"})
	reconcileExposure(t, f, "viewer", 2)

	exposure := getExposure(t, f, "viewer")
	requireCondition(t, exposure.Status.Conditions, reconcile.TypeAccepted, metav1.ConditionFalse, "UnsupportedTLSCoverage")
	requireCondition(t, exposure.Status.Conditions, reconcile.TypeProgrammed, metav1.ConditionFalse, "UnsupportedTLSCoverage")
	require.Equal(t, writesBefore, f.fake.WriteCount(),
		"no DNS record, Access Application, or tunnel rule may be programmed")
	require.Empty(t, exposure.Status.ProgrammedRule.Hostname)
}

func TestExposurePolicyMissingProgramsNothing(t *testing.T) {
	f := connectedLapras(t)
	convergedChain(t, f)
	f.createService(t, "viewer", 8080, false)

	writesBefore := f.fake.WriteCount()
	f.createExposure(t, exposureOptions{
		name: "viewer", module: "viewer", backend: "viewer",
		policies: []string{"atomi-admins", "absent-policy"},
	})
	reconcileExposure(t, f, "viewer", 2)

	exposure := getExposure(t, f, "viewer")
	requireCondition(t, exposure.Status.Conditions, reconcile.TypeResolvedRefs, metav1.ConditionFalse, "PolicyMissing")
	requireCondition(t, exposure.Status.Conditions, reconcile.TypeProgrammed, metav1.ConditionFalse, "PolicyMissing")
	require.Equal(t, writesBefore, f.fake.WriteCount(),
		"ANY missing policy programs NOTHING — no partial route, no subset attach")
}

func TestExposureBackendNotFoundRefused(t *testing.T) {
	f := connectedLapras(t)
	convergedChain(t, f)

	f.createExposure(t, exposureOptions{name: "viewer", module: "viewer", backend: "absent-service"})
	reconcileExposure(t, f, "viewer", 2)

	exposure := getExposure(t, f, "viewer")
	requireCondition(t, exposure.Status.Conditions, reconcile.TypeResolvedRefs, metav1.ConditionFalse, "BackendNotFound")
}

func TestExposureAdoptsExistingAccessApplication(t *testing.T) {
	f := connectedLapras(t)
	convergedChain(t, f)
	f.createService(t, "viewer", 8080, false)

	// Pre-existing application for the exact derived hostname(+path).
	hostname := "viewer.oxygen." + f.namespace + ".kirin.lapras.admin.atomi.cloud"
	credentials := cloudflare.Credentials{AccountID: "acc-" + f.namespace, APIToken: "good-token"}
	preexistingID, err := f.fake.CreateAccessApplication(context.Background(), credentials, cloudflare.AccessApplication{
		Name: "legacy", Hostname: hostname, Path: "/*", PolicyIDs: []string{"policy-2"},
	})
	require.NoError(t, err)

	f.createExposure(t, exposureOptions{name: "viewer", module: "viewer", backend: "viewer"})
	reconcileExposure(t, f, "viewer", 2)

	exposure := getExposure(t, f, "viewer")
	requireCondition(t, exposure.Status.Conditions, reconcile.TypeProgrammed, metav1.ConditionTrue, "Programmed")
	require.Equal(t, preexistingID, exposure.Status.AccessAppID, "must adopt, not duplicate")

	app := f.fake.Applications["acc-"+f.namespace+"/"+hostname+"/*"]
	require.Equal(t, []string{"policy-1"}, app.PolicyIDs, "adopted application converges to the CR's policy set")
}

func TestExposureDuplicateCreate409FallsBackToAdopt(t *testing.T) {
	f := connectedLapras(t)
	convergedChain(t, f)
	f.createService(t, "viewer", 8080, false)

	// RaceCreates registers the application and still 409s — exactly CF's
	// duplicate-create race. The reconcile must fall back to LIST-then-adopt.
	f.fake.RaceCreates = true
	f.createExposure(t, exposureOptions{name: "viewer", module: "viewer", backend: "viewer"})
	reconcileExposure(t, f, "viewer", 2)

	exposure := getExposure(t, f, "viewer")
	requireCondition(t, exposure.Status.Conditions, reconcile.TypeProgrammed, metav1.ConditionTrue, "Programmed")
	require.NotEmpty(t, exposure.Status.AccessAppID)

	// Idempotent across further reconciles: same id, no flapping.
	adoptedID := exposure.Status.AccessAppID
	reconcileExposure(t, f, "viewer", 2)
	require.Equal(t, adoptedID, getExposure(t, f, "viewer").Status.AccessAppID)
}

func TestExposureConflictOldestWinsDeterministically(t *testing.T) {
	f := connectedLapras(t)
	convergedChain(t, f)
	f.createService(t, "viewer", 8080, false)

	older := f.createExposure(t, exposureOptions{name: "older", module: "viewer", backend: "viewer"})
	// Force distinct creation timestamps: envtest stamps at second granularity.
	time.Sleep(1100 * time.Millisecond)
	f.createExposure(t, exposureOptions{name: "newer", module: "viewer", backend: "viewer"})

	for range 3 {
		reconcileExposure(t, f, "older", 2)
		reconcileExposure(t, f, "newer", 2)
	}

	olderGot := getExposure(t, f, "older")
	newerGot := getExposure(t, f, "newer")
	require.True(t, older.CreationTimestamp.Time.Before(newerGot.CreationTimestamp.Time))

	requireCondition(t, olderGot.Status.Conditions, reconcile.TypeProgrammed, metav1.ConditionTrue, "Programmed")
	requireCondition(t, olderGot.Status.Conditions, reconcile.TypeConflicted, metav1.ConditionFalse, "NoConflict")
	requireCondition(t, newerGot.Status.Conditions, reconcile.TypeConflicted, metav1.ConditionTrue, "HostnameConflict")
	requireCondition(t, newerGot.Status.Conditions, reconcile.TypeProgrammed, metav1.ConditionFalse, "HostnameConflict")
	require.Empty(t, newerGot.Status.ProgrammedRule.Hostname, "the conflicted loser holds no route")

	// Deterministic across re-reconciles — no flapping.
	reconcileExposure(t, f, "newer", 2)
	reconcileExposure(t, f, "older", 2)
	requireCondition(t, getExposure(t, f, "older").Status.Conditions, reconcile.TypeProgrammed, metav1.ConditionTrue, "Programmed")
	requireCondition(t, getExposure(t, f, "newer").Status.Conditions, reconcile.TypeConflicted, metav1.ConditionTrue, "HostnameConflict")
}

func TestExposureSharedBackendDeniedWithoutOptIn(t *testing.T) {
	f := connectedLapras(t)
	convergedChain(t, f)
	f.createService(t, "shared", 8080, true) // publicly routed backend

	f.createExposure(t, exposureOptions{name: "denied", module: "viewer", backend: "shared"})
	reconcileExposure(t, f, "denied", 2)
	denied := getExposure(t, f, "denied")
	requireCondition(t, denied.Status.Conditions, reconcile.TypeResolvedRefs, metav1.ConditionFalse, "SharedBackendDenied")
	requireCondition(t, denied.Status.Conditions, reconcile.TypeProgrammed, metav1.ConditionFalse, "SharedBackendDenied")

	f.createExposure(t, exposureOptions{name: "allowed", module: "editor", backend: "shared", shared: true})
	reconcileExposure(t, f, "allowed", 2)
	allowed := getExposure(t, f, "allowed")
	requireCondition(t, allowed.Status.Conditions, reconcile.TypeProgrammed, metav1.ConditionTrue, "Programmed")
}

// ─── Profile admission (DoD: hosted refusal + coordinate trust) ──────────────

func TestHostedProfilesCannotEnableBoron(t *testing.T) {
	for _, profile := range []string{"eevee", "plusle", "minun", "rotom", "absol"} {
		t.Run(profile, func(t *testing.T) {
			f := newFixture(t, reconcile.Installation{
				Profile: profile, Connected: true, DittoEnabled: true, Landscape: profile, Instance: "kirin",
			})
			convergedChain(t, f)
			f.createService(t, "viewer", 8080, false)

			writesBefore := f.fake.WriteCount()
			f.createExposure(t, exposureOptions{name: "viewer", module: "viewer", backend: "viewer"})
			reconcileExposure(t, f, "viewer", 2)

			exposure := getExposure(t, f, "viewer")
			requireCondition(t, exposure.Status.Conditions, reconcile.TypeAccepted, metav1.ConditionFalse, "ProfileUnsupported")
			require.Equal(t, writesBefore, f.fake.WriteCount(), "hosted/hermetic profiles never program exposures")
		})
	}
}

func TestDittoRequiresExplicitEnable(t *testing.T) {
	refused := newFixture(t, reconcile.Installation{
		Profile: reconcile.ProfileDitto, Connected: true, DittoEnabled: false, Landscape: "lapras", Instance: "kirin",
	})
	convergedChain(t, refused)
	refused.createService(t, "viewer", 8080, false)
	refused.createExposure(t, exposureOptions{name: "viewer", module: "viewer", backend: "viewer"})
	reconcileExposure(t, refused, "viewer", 2)
	requireCondition(t, getExposure(t, refused, "viewer").Status.Conditions, reconcile.TypeAccepted, metav1.ConditionFalse, "ProfileUnsupported")

	enabled := newFixture(t, reconcile.Installation{
		Profile: reconcile.ProfileDitto, Connected: true, DittoEnabled: true, Landscape: "lapras", Instance: "kirin",
	})
	convergedChain(t, enabled)
	enabled.createService(t, "viewer", 8080, false)
	enabled.createExposure(t, exposureOptions{name: "viewer", module: "viewer", backend: "viewer"})
	reconcileExposure(t, enabled, "viewer", 2)
	requireCondition(t, getExposure(t, enabled, "viewer").Status.Conditions, reconcile.TypeProgrammed, metav1.ConditionTrue, "Programmed")
}

func TestExposureCoordinatesMustMatchTrustedProfileMetadata(t *testing.T) {
	f := connectedLapras(t)
	convergedChain(t, f)
	f.createService(t, "viewer", 8080, false)

	f.createExposure(t, exposureOptions{name: "viewer", module: "viewer", backend: "viewer", instance: "not-kirin"})
	reconcileExposure(t, f, "viewer", 2)

	exposure := getExposure(t, f, "viewer")
	requireCondition(t, exposure.Status.Conditions, reconcile.TypeAccepted, metav1.ConditionFalse, "CoordinatesMismatch")
}

// ─── Toy CR converges AND a broken reconcile reddens ─────────────────────────

func TestToyCRConvergesAndBrokenReconcileReddens(t *testing.T) {
	f := connectedLapras(t)
	convergedChain(t, f)
	f.createService(t, "viewer", 8080, false)
	f.createExposure(t, exposureOptions{name: "toy", module: "viewer", backend: "viewer"})
	reconcileExposure(t, f, "toy", 2)
	requireCondition(t, getExposure(t, f, "toy").Status.Conditions, reconcile.TypeProgrammed, metav1.ConditionTrue, "Programmed")

	// Break the provider (policy disappears) — the same CR must redden and
	// release its route rather than stay green.
	delete(f.fake.Policies, "atomi-admins")
	reconcileExposure(t, f, "toy", 2)
	broken := getExposure(t, f, "toy")
	requireCondition(t, broken.Status.Conditions, reconcile.TypeResolvedRefs, metav1.ConditionFalse, "PolicyMissing")
	requireCondition(t, broken.Status.Conditions, reconcile.TypeProgrammed, metav1.ConditionFalse, "PolicyMissing")
	require.Empty(t, broken.Status.ProgrammedRule.Hostname)
}
