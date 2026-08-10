package operator_test

import (
	"context"
	"testing"

	"github.com/stretchr/testify/require"
	appsv1 "k8s.io/api/apps/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/types"

	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"

	apiv1alpha1 "github.com/AtomiCloud/diene.boron/api/v1alpha1"
)

func TestTunnelFinalizerRemovesOwnedDeploymentOnly(t *testing.T) {
	f := connectedLapras(t)
	convergedChain(t, f)

	var deployment appsv1.Deployment
	require.NoError(t, k8sClient.Get(context.Background(),
		client.ObjectKey{Namespace: f.namespace, Name: "cloudflared-admin"}, &deployment))

	tunnel := getTunnel(t, f, "admin")
	require.NoError(t, k8sClient.Delete(context.Background(), tunnel))
	reconcileTunnel(t, f, "admin", 2)

	err := k8sClient.Get(context.Background(),
		client.ObjectKey{Namespace: f.namespace, Name: "cloudflared-admin"}, &deployment)
	require.True(t, apierrors.IsNotFound(err) || !deployment.DeletionTimestamp.IsZero(),
		"owned cloudflared Deployment must be deleted on Tunnel finalization")

	var gone apiv1alpha1.Tunnel
	err = k8sClient.Get(context.Background(), client.ObjectKey{Namespace: f.namespace, Name: "admin"}, &gone)
	require.True(t, apierrors.IsNotFound(err), "finalizer must be removed and the Tunnel deleted")

	// The external tunnel record is never destroyed by the finalizer.
	require.Contains(t, f.fake.Tunnels, "acc-"+f.namespace+"/admin")
}

func TestExposureFinalizerCleansAccessAppAndDNS(t *testing.T) {
	f := connectedLapras(t)
	convergedChain(t, f)
	f.createService(t, "viewer", 8080, false)
	f.createExposure(t, exposureOptions{name: "viewer", module: "viewer", backend: "viewer"})
	reconcileExposure(t, f, "viewer", 2)

	exposure := getExposure(t, f, "viewer")
	hostname := exposure.Status.Hostname
	require.NotEmpty(t, exposure.Status.AccessAppID)
	dnsKey := "acc-" + f.namespace + "/admin.atomi.cloud/" + hostname
	require.Contains(t, f.fake.DNS, dnsKey)

	require.NoError(t, k8sClient.Delete(context.Background(), exposure))
	reconcileExposure(t, f, "viewer", 2)

	var gone apiv1alpha1.Exposure
	err := k8sClient.Get(context.Background(), client.ObjectKey{Namespace: f.namespace, Name: "viewer"}, &gone)
	require.True(t, apierrors.IsNotFound(err), "finalizer must be removed and the Exposure deleted")

	require.NotContains(t, f.fake.DNS, dnsKey, "the proxied CNAME is removed on finalization")
	appKey := "acc-" + f.namespace + "/" + hostname + "/*"
	require.NotContains(t, f.fake.Applications, appKey, "the Access Application is removed on finalization")
}

func TestWatchMappersTargetOnlyRelatedObjects(t *testing.T) {
	f := connectedLapras(t)
	convergedChain(t, f)
	f.createService(t, "viewer", 8080, false)
	exposure := f.createExposure(t, exposureOptions{name: "viewer", module: "viewer", backend: "viewer"})

	tunnel := getTunnel(t, f, "admin")
	account := getAccount(t, f, "main")

	// Exposure → its Tunnel.
	requests := callExposureToTunnel(f, exposure)
	require.Equal(t, []types.NamespacedName{{Namespace: f.namespace, Name: "admin"}}, requests)

	// Account → its Tunnels.
	requests = callAccountToTunnels(f, account)
	require.Equal(t, []types.NamespacedName{{Namespace: f.namespace, Name: "admin"}}, requests)

	// Tunnel → its Exposures.
	requests = callTunnelToExposures(f, tunnel)
	require.Equal(t, []types.NamespacedName{{Namespace: f.namespace, Name: "viewer"}}, requests)
}

func callExposureToTunnel(f *fixture, exposure *apiv1alpha1.Exposure) []types.NamespacedName {
	return names(f.tunnel.ExposureToTunnelRequests(context.Background(), exposure))
}

func callAccountToTunnels(f *fixture, account *apiv1alpha1.Account) []types.NamespacedName {
	return names(f.tunnel.AccountToTunnelRequests(context.Background(), account))
}

func callTunnelToExposures(f *fixture, tunnel *apiv1alpha1.Tunnel) []types.NamespacedName {
	return names(f.exposure.TunnelToExposureRequests(context.Background(), tunnel))
}

func names(requests []ctrl.Request) []types.NamespacedName {
	out := make([]types.NamespacedName, 0, len(requests))
	for _, r := range requests {
		out = append(out, r.NamespacedName)
	}
	return out
}
