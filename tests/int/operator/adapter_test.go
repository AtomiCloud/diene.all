package operator_test

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	"github.com/AtomiCloud/diene.boron/adapters/operator/controllers"
	"github.com/AtomiCloud/diene.boron/adapters/operator/kube"
)

func TestRealClockAdvances(t *testing.T) {
	before := time.Now().Add(-time.Second)
	now := kube.RealClock{}.Now()
	require.True(t, now.After(before))
}

func TestSecretAdapterVariants(t *testing.T) {
	f := connectedLapras(t)
	secrets := kube.NewSecretAdapter(k8sClient)

	// Absent secret.
	lookup, err := secrets.ReadToken(context.Background(), f.namespace, "absent")
	require.NoError(t, err)
	require.False(t, lookup.SecretFound)

	// Present but missing the token key.
	require.NoError(t, k8sClient.Create(context.Background(), &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Name: "empty", Namespace: f.namespace},
		Data:       map[string][]byte{"other": []byte("x")},
	}))
	lookup, err = secrets.ReadToken(context.Background(), f.namespace, "empty")
	require.NoError(t, err)
	require.True(t, lookup.SecretFound)
	require.False(t, lookup.TokenPresent)

	// Present with a token.
	f.createSecret(t, "full", "value")
	lookup, err = secrets.ReadToken(context.Background(), f.namespace, "full")
	require.NoError(t, err)
	require.True(t, lookup.TokenPresent)
	require.Equal(t, "value", lookup.Token)
}

func TestServiceAdapterVariants(t *testing.T) {
	f := connectedLapras(t)
	services := kube.NewServiceAdapter(k8sClient)

	lookup, err := services.ReadBackend(context.Background(), f.namespace, "absent", 80, controllers.PublicServiceAnnotation)
	require.NoError(t, err)
	require.False(t, lookup.Found)

	f.createService(t, "plain", 8080, false)
	lookup, err = services.ReadBackend(context.Background(), f.namespace, "plain", 8080, controllers.PublicServiceAnnotation)
	require.NoError(t, err)
	require.True(t, lookup.Found)
	require.True(t, lookup.PortFound)
	require.False(t, lookup.Public)

	// Wrong port.
	lookup, err = services.ReadBackend(context.Background(), f.namespace, "plain", 9999, controllers.PublicServiceAnnotation)
	require.NoError(t, err)
	require.True(t, lookup.Found)
	require.False(t, lookup.PortFound)

	f.createService(t, "public", 8080, true)
	lookup, err = services.ReadBackend(context.Background(), f.namespace, "public", 8080, controllers.PublicServiceAnnotation)
	require.NoError(t, err)
	require.True(t, lookup.Public)
}

func TestDeploymentAdapterDeleteAbsentIsNoop(t *testing.T) {
	f := connectedLapras(t)
	convergedChain(t, f)
	tunnel := getTunnel(t, f, "admin")
	adapter := kube.NewDeploymentAdapter(k8sClient, testScheme, controllers.TunnelOwnerLabel)
	require.NoError(t, adapter.DeleteDeployment(context.Background(), tunnel, "never-existed"))
}
