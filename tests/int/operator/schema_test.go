package operator_test

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/require"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"sigs.k8s.io/yaml"

	apiv1alpha1 "github.com/AtomiCloud/diene.boron/api/v1alpha1"
)

// The generated CRD schemas (committed goldens, drift-gated) must reject the
// invalid fixture and accept the valid one against the real apiserver.
func TestCRDSchemaRejectsInvalidExposureFixture(t *testing.T) {
	f := connectedLapras(t)

	raw, err := os.ReadFile(filepath.Join("..", "..", "fixtures", "operator", "invalid-exposure.yaml"))
	require.NoError(t, err)
	var obj unstructured.Unstructured
	require.NoError(t, yaml.Unmarshal(raw, &obj.Object))
	obj.SetNamespace(f.namespace)

	err = k8sClient.Create(context.Background(), &obj)
	require.Error(t, err, "the invalid fixture must be rejected by the CRD schema")
	for _, expected := range []string{"policies", "path", "port", "instance"} {
		require.Contains(t, err.Error(), expected, "schema rejection must name field %q", expected)
	}
}

func TestCRDSchemaAcceptsValidExposureFixtureWithDefaults(t *testing.T) {
	f := connectedLapras(t)

	raw, err := os.ReadFile(filepath.Join("..", "..", "fixtures", "operator", "valid-exposure.yaml"))
	require.NoError(t, err)
	var exposure apiv1alpha1.Exposure
	require.NoError(t, yaml.Unmarshal(raw, &exposure))
	exposure.Namespace = f.namespace

	require.NoError(t, k8sClient.Create(context.Background(), &exposure))

	var stored apiv1alpha1.Exposure
	require.NoError(t, k8sClient.Get(context.Background(),
		objectKey{Namespace: f.namespace, Name: "oxygen-viewer"}, &stored))
	require.Equal(t, "/*", stored.Spec.Path, "path defaulting must apply")
	require.False(t, stored.Spec.AllowSharedBackend)
}

func TestCRDSchemaRejectsInvalidSiblingSpecs(t *testing.T) {
	f := connectedLapras(t)

	badZone := &apiv1alpha1.Tunnel{
		ObjectMeta: metav1.ObjectMeta{Name: "bad-zone", Namespace: f.namespace},
		Spec: apiv1alpha1.TunnelSpec{
			AccountRef: apiv1alpha1.SecretNameReference{Name: "main"},
			Zone:       "NOT_A_ZONE",
		},
	}
	require.Error(t, k8sClient.Create(context.Background(), badZone), "zone pattern must reject invalid zones")

	emptyAccount := &apiv1alpha1.Account{
		ObjectMeta: metav1.ObjectMeta{Name: "empty", Namespace: f.namespace},
		Spec: apiv1alpha1.AccountSpec{
			AccountID:         "",
			APITokenSecretRef: apiv1alpha1.SecretNameReference{Name: "x"},
		},
	}
	require.Error(t, k8sClient.Create(context.Background(), emptyAccount), "accountId MinLength must reject empty")
}
