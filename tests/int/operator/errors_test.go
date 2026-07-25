package operator_test

import (
	"context"
	"testing"

	"github.com/stretchr/testify/require"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"

	"github.com/AtomiCloud/diene.boron/adapters/operator/cloudflare"
	apiv1alpha1 "github.com/AtomiCloud/diene.boron/api/v1alpha1"
	"github.com/AtomiCloud/diene.boron/lib/operator/reconcile"
)

// These tests exercise refusal and error branches a healthy envtest flow does
// not naturally produce.

func TestTunnelAccountSecretVanishesAfterReady(t *testing.T) {
	f := connectedLapras(t)
	convergedChain(t, f)

	// The Account is Ready, but its secret disappears before the next Tunnel
	// reconcile: the Tunnel must degrade to AccountNotReady, not crash.
	var secret corev1Secret
	require.NoError(t, k8sClient.Get(context.Background(),
		objectKey{Namespace: f.namespace, Name: "cf-edge-token"}, &secret))
	require.NoError(t, k8sClient.Delete(context.Background(), &secret))

	reconcileTunnel(t, f, "admin", 1)
	tunnel := getTunnel(t, f, "admin")
	requireCondition(t, tunnel.Status.Conditions, reconcile.TypeAccountNotReady, metav1.ConditionTrue, "AccountNotReady")
}

func TestExposurePathScopedAccessApplication(t *testing.T) {
	f := connectedLapras(t)
	convergedChain(t, f)
	f.createService(t, "viewer", 8080, false)
	f.createExposure(t, exposureOptions{name: "scoped", module: "viewer", backend: "viewer", path: "/api/*"})
	reconcileExposure(t, f, "scoped", 2)

	exposure := getExposure(t, f, "scoped")
	requireCondition(t, exposure.Status.Conditions, reconcile.TypeProgrammed, metav1.ConditionTrue, "Programmed")
	require.Equal(t, "/api/*", exposure.Status.ProgrammedRule.Path)

	hostname := exposure.Status.Hostname
	appKey := "acc-" + f.namespace + "/" + hostname + "/api/*"
	require.Contains(t, f.fake.Applications, appKey)
}

func TestExposureUnsupportedPathRefused(t *testing.T) {
	f := connectedLapras(t)
	convergedChain(t, f)
	f.createService(t, "viewer", 8080, false)
	f.createExposure(t, exposureOptions{name: "finer", module: "viewer", backend: "viewer", path: "/api*"})
	reconcileExposure(t, f, "finer", 2)

	exposure := getExposure(t, f, "finer")
	requireCondition(t, exposure.Status.Conditions, reconcile.TypeAccepted, metav1.ConditionFalse, "UnsupportedMatch")
}

func TestExposureTunnelRefMissingRefused(t *testing.T) {
	f := connectedLapras(t)
	f.createService(t, "viewer", 8080, false)
	f.createExposure(t, exposureOptions{name: "orphan", module: "viewer", backend: "viewer"})
	reconcileExposure(t, f, "orphan", 2)

	exposure := getExposure(t, f, "orphan")
	requireCondition(t, exposure.Status.Conditions, reconcile.TypeAccepted, metav1.ConditionFalse, "TunnelMissing")
}

func TestExposureFinalizerWithoutProgrammedStateIsClean(t *testing.T) {
	f := connectedLapras(t)
	f.createService(t, "viewer", 8080, false)
	exposure := f.createExposure(t, exposureOptions{name: "shortlived", module: "viewer", backend: "viewer"})
	reconcileExposure(t, f, "shortlived", 2) // refused: no tunnel — nothing programmed

	require.NoError(t, k8sClient.Delete(context.Background(), exposure))
	reconcileExposure(t, f, "shortlived", 2)

	var gone apiv1alpha1.Exposure
	err := k8sClient.Get(context.Background(), objectKey{Namespace: f.namespace, Name: "shortlived"}, &gone)
	require.True(t, isNotFound(err), "an unprogrammed Exposure finalizes without provider calls")
}

func TestHTTPHostCoversWildcardSemantics(t *testing.T) {
	adapter, fake := newHTTPAdapter(t)
	fake.certHosts = []string{"*.admin.atomi.cloud"}

	// One label under the wildcard is covered.
	oneLabel, err := adapter.CheckTLSCoverage(context.Background(), goodCredentials,
		"admin.atomi.cloud", "api.admin.atomi.cloud")
	require.NoError(t, err)
	require.True(t, oneLabel.Covered)

	// The deeper canonical dotted hostname is NOT covered by a one-label wildcard.
	deep, err := adapter.CheckTLSCoverage(context.Background(), goodCredentials,
		"admin.atomi.cloud", "viewer.oxygen.nitroso.kirin.lapras.admin.atomi.cloud")
	require.NoError(t, err)
	require.False(t, deep.Covered, "a one-label wildcard never covers the multi-label form")
}

func TestHTTPInvalidTokenSurfacesTypedError(t *testing.T) {
	adapter, _ := newHTTPAdapter(t)
	badCredentials := cloudflare.Credentials{AccountID: "acc-1", APIToken: "wrong"}

	_, err := adapter.EnsureTunnel(context.Background(), badCredentials, "admin", "admin.atomi.cloud")
	require.ErrorIs(t, err, cloudflare.ErrInvalidToken)

	_, err = adapter.LookupPolicies(context.Background(), badCredentials, []string{"atomi-admins"})
	require.ErrorIs(t, err, cloudflare.ErrInvalidToken)

	err = adapter.PushTunnelConfig(context.Background(), badCredentials, "tun-1", nil)
	require.ErrorIs(t, err, cloudflare.ErrInvalidToken)
}

// Small local aliases to keep the test bodies terse.
type corev1Secret = corev1.Secret

type objectKey = client.ObjectKey

func isNotFound(err error) bool { return apierrors.IsNotFound(err) }
