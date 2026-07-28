package operator_test

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/tools/record"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"

	// The controllers sentinel is a selected coverage package with no exported
	// surface, so a blank import is the only way to link it into the int-tier
	// test binary. That makes the test dependency closure cover every selected
	// adapter package and silences the -coverpkg "no packages being tested
	// depend on" warning; the package has zero statements, so no coverage
	// numerator or denominator changes.
	_ "github.com/AtomiCloud/diene.fleet-operator/adapters/operator/controllers"
	"github.com/AtomiCloud/diene.fleet-operator/adapters/operator/kube"
)

const kubeAdapterOwnerLabel = "fleet.atomi.cloud/owner"

func newKubeAdapter() kube.ConfigMapAdapter {
	return kube.NewConfigMapAdapter(k8sClient, testScheme, kubeAdapterOwnerLabel)
}

// makeOwner creates a real API-server object whose UID anchors controller
// ownership for the adapter under test.
func makeOwner(t *testing.T, name string) *corev1.ConfigMap {
	t.Helper()
	owner := &corev1.ConfigMap{
		ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: "default"},
	}
	require.NoError(t, k8sClient.Create(context.Background(), owner))
	return owner
}

func makeForeignConfigMap(t *testing.T, name string) {
	t.Helper()
	require.NoError(t, k8sClient.Create(context.Background(), &corev1.ConfigMap{
		ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: "default"},
	}))
}

func getConfigMap(t *testing.T, name string) *corev1.ConfigMap {
	t.Helper()
	var cm corev1.ConfigMap
	key := client.ObjectKey{Namespace: "default", Name: name}
	require.NoError(t, k8sClient.Get(context.Background(), key, &cm))
	return &cm
}

func TestKubeAdapterUpsertCreatesOwnedConfigMap(t *testing.T) {
	owner := makeOwner(t, "kube-adapter-create-owner")
	adapter := newKubeAdapter()

	require.NoError(t, adapter.Upsert(context.Background(), owner, "kube-adapter-created", "payload-1"))

	cm := getConfigMap(t, "kube-adapter-created")
	require.Equal(t, "payload-1", cm.Data["payload"])
	require.Equal(t, owner.GetName(), cm.Labels[kubeAdapterOwnerLabel])
	ref := metav1.GetControllerOf(cm)
	require.NotNil(t, ref)
	require.Equal(t, owner.GetUID(), ref.UID)
}

func TestKubeAdapterUpsertIsIdempotentAndUpdates(t *testing.T) {
	owner := makeOwner(t, "kube-adapter-update-owner")
	adapter := newKubeAdapter()

	require.NoError(t, adapter.Upsert(context.Background(), owner, "kube-adapter-updated", "same"))
	before := getConfigMap(t, "kube-adapter-updated")
	require.NoError(t, adapter.Upsert(context.Background(), owner, "kube-adapter-updated", "same"))
	unchanged := getConfigMap(t, "kube-adapter-updated")
	require.Equal(t, before.ResourceVersion, unchanged.ResourceVersion)

	require.NoError(t, adapter.Upsert(context.Background(), owner, "kube-adapter-updated", "changed"))
	require.Equal(t, "changed", getConfigMap(t, "kube-adapter-updated").Data["payload"])
}

func TestKubeAdapterUpsertRepairsNilPayloadMap(t *testing.T) {
	owner := makeOwner(t, "kube-adapter-nil-owner")
	adapter := newKubeAdapter()

	owned := &corev1.ConfigMap{
		ObjectMeta: metav1.ObjectMeta{Name: "kube-adapter-nil-data", Namespace: "default"},
	}
	require.NoError(t, controllerutil.SetControllerReference(owner, owned, testScheme))
	require.NoError(t, k8sClient.Create(context.Background(), owned))

	require.NoError(t, adapter.Upsert(context.Background(), owner, "kube-adapter-nil-data", "repaired"))
	require.Equal(t, "repaired", getConfigMap(t, "kube-adapter-nil-data").Data["payload"])
}

func TestKubeAdapterUpsertRejectsForeignConfigMap(t *testing.T) {
	owner := makeOwner(t, "kube-adapter-conflict-owner")
	makeForeignConfigMap(t, "kube-adapter-foreign-conflict")

	err := newKubeAdapter().Upsert(context.Background(), owner, "kube-adapter-foreign-conflict", "x")
	require.True(t, apierrors.IsAlreadyExists(err))
}

func TestKubeAdapterUpsertReportsUnregisteredOwnerScheme(t *testing.T) {
	owner := makeOwner(t, "kube-adapter-scheme-owner")
	bare := kube.NewConfigMapAdapter(k8sClient, runtime.NewScheme(), kubeAdapterOwnerLabel)

	require.Error(t, bare.Upsert(context.Background(), owner, "kube-adapter-scheme-target", "x"))
}

func TestKubeAdapterListOwnedClassifiesOwnership(t *testing.T) {
	owner := makeOwner(t, "kube-adapter-list-owner")
	adapter := newKubeAdapter()

	require.NoError(t, adapter.Upsert(context.Background(), owner, "kube-adapter-list-owned", "v"))
	makeForeignConfigMap(t, "kube-adapter-list-foreign")
	makeForeignConfigMap(t, "kube-adapter-list-unrelated")

	owned, foreign, err := adapter.ListOwned(context.Background(), owner,
		[]string{"kube-adapter-list-owned", "kube-adapter-list-foreign"})
	require.NoError(t, err)
	require.Equal(t, []kube.OwnedConfigMap{{Name: "kube-adapter-list-owned", Payload: "v"}}, owned)
	require.Equal(t, []string{"kube-adapter-list-foreign"}, foreign)
}

func TestKubeAdapterDeleteRemovesOnlyOwned(t *testing.T) {
	owner := makeOwner(t, "kube-adapter-delete-owner")
	adapter := newKubeAdapter()

	require.NoError(t, adapter.Upsert(context.Background(), owner, "kube-adapter-delete-owned", "v"))
	makeForeignConfigMap(t, "kube-adapter-delete-foreign")

	require.NoError(t, adapter.Delete(context.Background(), owner, "kube-adapter-delete-owned"))
	var gone corev1.ConfigMap
	err := k8sClient.Get(context.Background(),
		client.ObjectKey{Namespace: "default", Name: "kube-adapter-delete-owned"}, &gone)
	require.True(t, apierrors.IsNotFound(err))

	require.NoError(t, adapter.Delete(context.Background(), owner, "kube-adapter-delete-foreign"))
	getConfigMap(t, "kube-adapter-delete-foreign")

	require.NoError(t, adapter.Delete(context.Background(), owner, "kube-adapter-delete-absent"))
}

func TestKubeAdapterSurfacesTransportErrors(t *testing.T) {
	owner := makeOwner(t, "kube-adapter-cancel-owner")
	adapter := newKubeAdapter()
	cancelled, cancel := context.WithCancel(context.Background())
	cancel()

	_, _, err := adapter.ListOwned(cancelled, owner, nil)
	require.Error(t, err)
	require.Error(t, adapter.Upsert(cancelled, owner, "kube-adapter-cancel-target", "x"))
	require.Error(t, adapter.Delete(cancelled, owner, "kube-adapter-cancel-target"))
}

func TestKubeRealClockTracksWallClock(t *testing.T) {
	require.WithinDuration(t, time.Now(), kube.RealClock{}.Now(), time.Minute)
}

func TestKubeEventRecorderForwardsEvents(t *testing.T) {
	sink := record.NewFakeRecorder(1)
	owner := makeOwner(t, "kube-adapter-event-owner")

	kube.NewEventRecorder(sink).Event(owner, corev1.EventTypeNormal, "Converged", "adapter event")

	select {
	case event := <-sink.Events:
		require.Contains(t, event, "Converged")
	default:
		t.Fatal("no event forwarded to the recorder sink")
	}
}
