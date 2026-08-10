package operator_test

import (
	"context"
	"flag"
	"io"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	apimeta "k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"

	"github.com/AtomiCloud/diene.boron/adapters/operator/cloudflare"
	"github.com/AtomiCloud/diene.boron/adapters/operator/metrics"
	apiv1alpha1 "github.com/AtomiCloud/diene.boron/api/v1alpha1"
	"github.com/AtomiCloud/diene.boron/internal/operatorruntime"
	"github.com/AtomiCloud/diene.boron/lib/operator/reconcile"
)

// TestMultiControllerWiring proves the manager registers all three controllers
// from real flags and converges a full Account → Tunnel → Exposure chain
// end-to-end through the shared cache.
func TestMultiControllerWiring(t *testing.T) {
	config := operatorruntime.Config{}
	flags := flag.NewFlagSet("manager-acceptance", flag.ContinueOnError)
	flags.SetOutput(io.Discard)
	operatorruntime.BindFlags(flags, &config)
	require.NoError(t, flags.Parse([]string{
		"--enable-account=true",
		"--enable-tunnel=true",
		"--enable-exposure=true",
		"--leader-elect=false",
		"--metrics-bind-address=0",
		"--health-probe-bind-address=0",
		"--install-profile=lapras",
		"--connected=true",
		"--landscape=lapras",
		"--instance=kirin",
		"--cloudflared-image=cloudflare/cloudflared:2025.7.0",
	}))
	require.True(t, config.EnableAccount)
	require.True(t, config.EnableTunnel)
	require.True(t, config.EnableExposure)
	require.False(t, config.LeaderElection)

	fake := cloudflare.NewMemory()
	fake.Policies["atomi-admins"] = "policy-1"

	manager, err := operatorruntime.NewManager(restConfig, testScheme, config)
	require.NoError(t, err)
	require.NoError(t, operatorruntime.RegisterControllers(manager, config, operatorruntime.ControllerDependencies{
		Clock:    fakeClock{t: time.Unix(1700000000, 0).UTC()},
		Metrics:  metrics.NewPrometheus(),
		Provider: fake,
	}))

	managerContext, stopManager := context.WithCancel(context.Background())
	managerDone := make(chan error, 1)
	go func() {
		managerDone <- manager.Start(managerContext)
	}()
	t.Cleanup(func() {
		stopManager()
		require.NoError(t, <-managerDone)
	})

	cacheContext, stopCacheWait := context.WithTimeout(managerContext, 10*time.Second)
	defer stopCacheWait()
	require.True(t, manager.GetCache().WaitForCacheSync(cacheContext))

	namespace := "wiring"
	require.NoError(t, k8sClient.Create(context.Background(), &corev1.Namespace{ObjectMeta: metav1.ObjectMeta{Name: namespace}}))
	require.NoError(t, k8sClient.Create(context.Background(), &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Name: "cf-edge-token", Namespace: namespace},
		Data:       map[string][]byte{"token": []byte("wiring-token")},
	}))
	require.NoError(t, k8sClient.Create(context.Background(), &corev1.Service{
		ObjectMeta: metav1.ObjectMeta{Name: "viewer", Namespace: namespace},
		Spec: corev1.ServiceSpec{
			Ports: []corev1.ServicePort{{Port: 8080}},
		},
	}))

	account := &apiv1alpha1.Account{
		ObjectMeta: metav1.ObjectMeta{Name: "main", Namespace: namespace},
		Spec: apiv1alpha1.AccountSpec{
			AccountID:         "acc-wiring",
			APITokenSecretRef: apiv1alpha1.SecretNameReference{Name: "cf-edge-token"},
		},
	}
	tunnel := &apiv1alpha1.Tunnel{
		ObjectMeta: metav1.ObjectMeta{Name: "admin", Namespace: namespace},
		Spec: apiv1alpha1.TunnelSpec{
			AccountRef: apiv1alpha1.SecretNameReference{Name: "main"},
			Zone:       "admin.atomi.cloud",
		},
	}
	exposure := &apiv1alpha1.Exposure{
		ObjectMeta: metav1.ObjectMeta{Name: "viewer", Namespace: namespace},
		Spec: apiv1alpha1.ExposureSpec{
			TunnelRef: apiv1alpha1.SecretNameReference{Name: "admin"},
			Coordinates: apiv1alpha1.Coordinates{
				Landscape: "lapras", Platform: namespace, Service: "oxygen", Module: "viewer",
			},
			Instance: "kirin",
			Backend:  apiv1alpha1.BackendReference{Name: "viewer", Port: 8080},
			Policies: []string{"atomi-admins"},
		},
	}
	require.NoError(t, k8sClient.Create(context.Background(), account))
	require.NoError(t, k8sClient.Create(context.Background(), tunnel))
	require.NoError(t, k8sClient.Create(context.Background(), exposure))

	require.Eventually(t, func() bool {
		var current apiv1alpha1.Account
		if err := k8sClient.Get(context.Background(), client.ObjectKeyFromObject(account), &current); err != nil {
			return false
		}
		ready := apimeta.FindStatusCondition(current.Status.Conditions, reconcile.TypeReady)
		return ready != nil && ready.Status == metav1.ConditionTrue
	}, 15*time.Second, 100*time.Millisecond, "Account controller did not converge")

	require.Eventually(t, func() bool {
		var current apiv1alpha1.Tunnel
		if err := k8sClient.Get(context.Background(), client.ObjectKeyFromObject(tunnel), &current); err != nil {
			return false
		}
		synced := apimeta.FindStatusCondition(current.Status.Conditions, reconcile.TypeConfigSynced)
		return synced != nil && synced.Status == metav1.ConditionTrue && current.Status.TunnelID != ""
	}, 15*time.Second, 100*time.Millisecond, "Tunnel controller did not converge")

	require.Eventually(t, func() bool {
		var current apiv1alpha1.Exposure
		if err := k8sClient.Get(context.Background(), client.ObjectKeyFromObject(exposure), &current); err != nil {
			return false
		}
		programmed := apimeta.FindStatusCondition(current.Status.Conditions, reconcile.TypeProgrammed)
		return programmed != nil && programmed.Status == metav1.ConditionTrue &&
			current.Status.Hostname == "viewer.oxygen.wiring.kirin.lapras.admin.atomi.cloud"
	}, 15*time.Second, 100*time.Millisecond, "Exposure controller did not converge")

	var deployment appsv1.Deployment
	require.NoError(t, k8sClient.Get(context.Background(),
		client.ObjectKey{Namespace: namespace, Name: "cloudflared-admin"}, &deployment))
	require.NotNil(t, deployment.Spec.Replicas)
	require.Equal(t, reconcile.TunnelReplicas, *deployment.Spec.Replicas)
}
