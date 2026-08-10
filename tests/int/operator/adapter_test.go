package operator_test

import (
	"context"
	"testing"

	"github.com/stretchr/testify/require"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"

	"github.com/AtomiCloud/diene.go-base/adapters/operator/controllers"
	"github.com/AtomiCloud/diene.go-base/adapters/operator/kube"
)

func newAdapter() kube.ConfigMapAdapter {
	return kube.NewConfigMapAdapter(k8sClient, testScheme, controllers.NoteOwnerLabel)
}

func createForeign(t *testing.T, name string) {
	t.Helper()
	require.NoError(t, k8sClient.Create(context.Background(), &corev1.ConfigMap{
		ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: "default"},
	}))
}

func TestAdapterUpsertRejectsForeign(t *testing.T) {
	createForeign(t, "adapter-foreign-1")
	makeNote(t, "adapter-owner-1", "work", 1)
	err := newAdapter().Upsert(context.Background(), getNote(t, "adapter-owner-1"), "adapter-foreign-1", "x")
	require.True(t, apierrors.IsAlreadyExists(err))
}

func TestAdapterDeleteSkipsForeign(t *testing.T) {
	createForeign(t, "adapter-foreign-2")
	makeNote(t, "adapter-owner-2", "work", 1)
	require.NoError(t, newAdapter().Delete(context.Background(), getNote(t, "adapter-owner-2"), "adapter-foreign-2"))
	var after corev1.ConfigMap
	require.NoError(t, k8sClient.Get(context.Background(), client.ObjectKey{Namespace: "default", Name: "adapter-foreign-2"}, &after))
}

func TestAdapterDeleteAbsentIsNoOp(t *testing.T) {
	makeNote(t, "adapter-owner-3", "work", 1)
	require.NoError(t, newAdapter().Delete(context.Background(), getNote(t, "adapter-owner-3"), "adapter-absent"))
}
