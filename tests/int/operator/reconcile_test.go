package operator_test

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	corev1 "k8s.io/api/core/v1"
	apimeta "k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/tools/record"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/manager"
	metricsserver "sigs.k8s.io/controller-runtime/pkg/metrics/server"

	"github.com/AtomiCloud/diene.go-base/adapters/operator/controllers"
	"github.com/AtomiCloud/diene.go-base/adapters/operator/kube"
	"github.com/AtomiCloud/diene.go-base/adapters/operator/metrics"
	apiv1alpha1 "github.com/AtomiCloud/diene.go-base/api/v1alpha1"
	"github.com/AtomiCloud/diene.go-base/lib/operator/ledger"
	"github.com/AtomiCloud/diene.go-base/lib/operator/plan"
)

// fakeLedgerStore is an in-memory ledger.Store so the envtest reconcile tests run
// without Docker; the MinIO adapter is covered by ledger_minio_test.go.
type fakeLedgerStore struct{ entries map[string]ledger.Entry }

func newFakeLedgerStore() *fakeLedgerStore {
	return &fakeLedgerStore{entries: map[string]ledger.Entry{}}
}

func (s *fakeLedgerStore) Get(_ context.Context, key string) (ledger.Entry, bool, error) {
	e, ok := s.entries[key]
	return e, ok, nil
}

func (s *fakeLedgerStore) Put(_ context.Context, e ledger.Entry) error {
	s.entries[e.Coordinate.Key()] = e
	return nil
}

type fakeClock struct{ t time.Time }

func (c fakeClock) Now() time.Time { return c.t }

func newNoteReconciler(store ledger.Store, observe bool, brakeCap int) *controllers.NoteReconciler {
	return &controllers.NoteReconciler{
		Client:     k8sClient,
		Clock:      fakeClock{t: time.Unix(1700000000, 0).UTC()},
		Recorder:   kube.NewEventRecorder(record.NewFakeRecorder(64)),
		ConfigMaps: kube.NewConfigMapAdapter(k8sClient, testScheme, controllers.NoteOwnerLabel),
		Ledger:     ledger.NewService(store),
		Metrics:    metrics.NewPrometheus(),
		Observe:    observe,
		BrakeCap:   brakeCap,
		Platform:   "diene",
		Landscape:  "lapras",
	}
}

func reconcileNote(t *testing.T, r *controllers.NoteReconciler, name string, times int) {
	t.Helper()
	key := client.ObjectKey{Namespace: "default", Name: name}
	for range times {
		_, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: key})
		require.NoError(t, err)
	}
}

func getNote(t *testing.T, name string) *apiv1alpha1.Note {
	t.Helper()
	var note apiv1alpha1.Note
	require.NoError(t, k8sClient.Get(context.Background(), client.ObjectKey{Namespace: "default", Name: name}, &note))
	return &note
}

func makeNote(t *testing.T, name, category string, replicas int32) {
	t.Helper()
	note := &apiv1alpha1.Note{
		ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: "default"},
		Spec:       apiv1alpha1.NoteSpec{Title: "Title " + name, Body: "body", Category: category, Replicas: replicas},
	}
	require.NoError(t, k8sClient.Create(context.Background(), note))
}

func ownedConfigMaps(t *testing.T, owner string) []corev1.ConfigMap {
	t.Helper()
	var list corev1.ConfigMapList
	require.NoError(t, k8sClient.List(context.Background(), &list, client.InNamespace("default")))
	var out []corev1.ConfigMap
	for i := range list.Items {
		ref := metav1.GetControllerOf(&list.Items[i])
		note := getNoteOrNil(owner)
		if ref != nil && note != nil && ref.UID == note.UID {
			out = append(out, list.Items[i])
		}
	}
	return out
}

func getNoteOrNil(name string) *apiv1alpha1.Note {
	var note apiv1alpha1.Note
	if err := k8sClient.Get(context.Background(), client.ObjectKey{Namespace: "default", Name: name}, &note); err != nil {
		return nil
	}
	return &note
}

func TestNoteConvergesToReadyAndConfirmed(t *testing.T) {
	store := newFakeLedgerStore()
	r := newNoteReconciler(store, false, 20)
	makeNote(t, "converge", "work", 2)
	reconcileNote(t, r, "converge", 2)

	got := getNote(t, "converge")
	require.Equal(t, int32(2), got.Status.OwnedConfigMaps)
	require.Equal(t, "diene/lapras/note/converge", got.Status.LedgerRef)
	ready := apimeta.FindStatusCondition(got.Status.Conditions, plan.TypeReady)
	require.NotNil(t, ready)
	require.Equal(t, metav1.ConditionTrue, ready.Status)
	require.Len(t, ownedConfigMaps(t, "converge"), 2)

	entry, ok, _ := store.Get(context.Background(), "diene/lapras/note/converge")
	require.True(t, ok)
	require.Equal(t, ledger.PhaseConfirmed, entry.Phase) // Ready only after confirm
}

func TestNoteContentUpdate(t *testing.T) {
	r := newNoteReconciler(newFakeLedgerStore(), false, 20)
	makeNote(t, "update", "work", 1)
	reconcileNote(t, r, "update", 2)

	current := getNote(t, "update")
	current.Spec.Body = "changed body"
	require.NoError(t, k8sClient.Update(context.Background(), current))
	reconcileNote(t, r, "update", 1)

	cms := ownedConfigMaps(t, "update")
	require.Len(t, cms, 1)
	require.Contains(t, cms[0].Data["payload"], "changed body")
}

func TestNoteFinalizerLifecycle(t *testing.T) {
	store := newFakeLedgerStore()
	r := newNoteReconciler(store, false, 20)
	makeNote(t, "finalized", "personal", 1)
	reconcileNote(t, r, "finalized", 2)
	require.Contains(t, getNote(t, "finalized").Finalizers, apiv1alpha1.NoteFinalizer)

	require.NoError(t, k8sClient.Delete(context.Background(), getNote(t, "finalized")))
	reconcileNote(t, r, "finalized", 1)

	require.Nil(t, getNoteOrNil("finalized"))
	entry, ok, _ := store.Get(context.Background(), "diene/lapras/note/finalized")
	require.True(t, ok)
	require.Equal(t, ledger.PhaseOrphaned, entry.Phase)
}

func TestNoteOrphanReapplyConfirmed(t *testing.T) {
	store := newFakeLedgerStore()
	r := newNoteReconciler(store, false, 20)
	makeNote(t, "readopt", "work", 1)
	reconcileNote(t, r, "readopt", 2)
	require.NoError(t, k8sClient.Delete(context.Background(), getNote(t, "readopt")))
	reconcileNote(t, r, "readopt", 1)
	orphaned, _, _ := store.Get(context.Background(), "diene/lapras/note/readopt")
	require.Equal(t, ledger.PhaseOrphaned, orphaned.Phase)

	// Re-create the same coordinate: the orphaned entry must be adopted back and
	// end confirmed, preserving the external ID, never remaining orphaned.
	makeNote(t, "readopt", "work", 1)
	reconcileNote(t, r, "readopt", 2)
	readopted, ok, _ := store.Get(context.Background(), "diene/lapras/note/readopt")
	require.True(t, ok)
	require.Equal(t, ledger.PhaseConfirmed, readopted.Phase)
	require.Equal(t, orphaned.ExternalID, readopted.ExternalID)
	ready := apimeta.FindStatusCondition(getNote(t, "readopt").Status.Conditions, plan.TypeReady)
	require.Equal(t, metav1.ConditionTrue, ready.Status)
}

func TestNoteObserveDrift(t *testing.T) {
	r := newNoteReconciler(newFakeLedgerStore(), true, 20)
	makeNote(t, "observe-drift", "work", 2)
	reconcileNote(t, r, "observe-drift", 2)
	drifted := apimeta.FindStatusCondition(getNote(t, "observe-drift").Status.Conditions, plan.TypeDrifted)
	require.NotNil(t, drifted)
	require.Equal(t, metav1.ConditionTrue, drifted.Status)
	require.Empty(t, ownedConfigMaps(t, "observe-drift"))
}

func TestNoteObserveInSync(t *testing.T) {
	store := newFakeLedgerStore()
	makeNote(t, "observe-sync", "archive", 1)
	reconcileNote(t, newNoteReconciler(store, false, 20), "observe-sync", 2)
	reconcileNote(t, newNoteReconciler(store, true, 20), "observe-sync", 1)
	drifted := apimeta.FindStatusCondition(getNote(t, "observe-sync").Status.Conditions, plan.TypeDrifted)
	require.Equal(t, metav1.ConditionFalse, drifted.Status)
}

func TestNoteBlastBrakeTrips(t *testing.T) {
	r := newNoteReconciler(newFakeLedgerStore(), false, 20)
	makeNote(t, "brake", "work", 4)
	reconcileNote(t, r, "brake", 2)
	require.Len(t, ownedConfigMaps(t, "brake"), 4)

	current := getNote(t, "brake")
	current.Spec.Replicas = 1
	require.NoError(t, k8sClient.Update(context.Background(), current))
	reconcileNote(t, r, "brake", 1)

	tripped := apimeta.FindStatusCondition(getNote(t, "brake").Status.Conditions, plan.TypeBlastBrakeTripped)
	require.NotNil(t, tripped)
	require.Equal(t, metav1.ConditionTrue, tripped.Status)
	require.Len(t, ownedConfigMaps(t, "brake"), 4) // wrote nothing
}

func TestNoteConflictForeignConfigMap(t *testing.T) {
	// A foreign ConfigMap occupies the desired copy-0 name; ownership is by UID, so
	// it must not be overwritten and the Note must surface Conflict.
	foreign := &corev1.ConfigMap{
		ObjectMeta: metav1.ObjectMeta{Name: "conflict-copy-0", Namespace: "default"},
		Data:       map[string]string{"payload": "foreign-owned"},
	}
	require.NoError(t, k8sClient.Create(context.Background(), foreign))

	r := newNoteReconciler(newFakeLedgerStore(), false, 20)
	makeNote(t, "conflict", "work", 1)
	reconcileNote(t, r, "conflict", 2)

	cond := apimeta.FindStatusCondition(getNote(t, "conflict").Status.Conditions, plan.TypeConflict)
	require.NotNil(t, cond)
	require.Equal(t, metav1.ConditionTrue, cond.Status)

	var after corev1.ConfigMap
	require.NoError(t, k8sClient.Get(context.Background(), client.ObjectKey{Namespace: "default", Name: "conflict-copy-0"}, &after))
	require.Equal(t, "foreign-owned", after.Data["payload"]) // never overwritten
}

func TestSpoofLabelledConfigMapSurvives(t *testing.T) {
	// A ConfigMap carrying the owner label but no controller OwnerReference must
	// never be counted or deleted during scale-down or finalization.
	spoof := &corev1.ConfigMap{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "spoof-not-owned",
			Namespace: "default",
			Labels:    map[string]string{controllers.NoteOwnerLabel: "spoofed"},
		},
	}
	require.NoError(t, k8sClient.Create(context.Background(), spoof))

	r := newNoteReconciler(newFakeLedgerStore(), false, 20)
	makeNote(t, "spoofed", "work", 1)
	reconcileNote(t, r, "spoofed", 2)
	require.Equal(t, int32(1), getNote(t, "spoofed").Status.OwnedConfigMaps) // spoof not counted

	require.NoError(t, k8sClient.Delete(context.Background(), getNote(t, "spoofed")))
	reconcileNote(t, r, "spoofed", 1)

	var survivor corev1.ConfigMap
	require.NoError(t, k8sClient.Get(context.Background(), client.ObjectKey{Namespace: "default", Name: "spoof-not-owned"}, &survivor))
}

func TestNoteWaitingForEndpointOnLedgerFailure(t *testing.T) {
	r := newNoteReconciler(failingLedgerStore{}, false, 20)
	makeNote(t, "waiting", "work", 1)
	// First reconcile adds the finalizer; the second hits the failing ledger.
	key := client.ObjectKey{Namespace: "default", Name: "waiting"}
	_, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: key})
	require.NoError(t, err)
	_, err = r.Reconcile(context.Background(), ctrl.Request{NamespacedName: key})
	require.Error(t, err)
	waiting := apimeta.FindStatusCondition(getNote(t, "waiting").Status.Conditions, plan.TypeWaitingForEndpoint)
	require.NotNil(t, waiting)
	require.Equal(t, metav1.ConditionTrue, waiting.Status)
}

func TestNoteReconcileMissingIsNoOp(t *testing.T) {
	r := newNoteReconciler(newFakeLedgerStore(), false, 20)
	_, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: client.ObjectKey{Namespace: "default", Name: "ghost"}})
	require.NoError(t, err)
}

func TestJournalReconcile(t *testing.T) {
	journal := &apiv1alpha1.Journal{
		ObjectMeta: metav1.ObjectMeta{Name: "jrnl", Namespace: "default"},
		Spec:       apiv1alpha1.JournalSpec{Message: "first entry"},
	}
	require.NoError(t, k8sClient.Create(context.Background(), journal))
	r := &controllers.JournalReconciler{
		Client:   k8sClient,
		Clock:    fakeClock{t: time.Unix(1700000000, 0).UTC()},
		Recorder: kube.NewEventRecorder(record.NewFakeRecorder(8)),
		Metrics:  metrics.NewPrometheus(),
	}
	_, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: client.ObjectKeyFromObject(journal)})
	require.NoError(t, err)
	var got apiv1alpha1.Journal
	require.NoError(t, k8sClient.Get(context.Background(), client.ObjectKeyFromObject(journal), &got))
	require.Equal(t, metav1.ConditionTrue, apimeta.FindStatusCondition(got.Status.Conditions, plan.TypeReady).Status)
}

func TestInvalidNoteRejectedBySchema(t *testing.T) {
	invalid := &apiv1alpha1.Note{
		ObjectMeta: metav1.ObjectMeta{Name: "invalid", Namespace: "default"},
		Spec:       apiv1alpha1.NoteSpec{Title: "t", Body: "b", Category: "nonsense", Replicas: 1},
	}
	require.Error(t, k8sClient.Create(context.Background(), invalid))
}

func TestMultiControllerWiring(t *testing.T) {
	mgr, err := manager.New(restConfig, manager.Options{Scheme: testScheme, Metrics: metricsserver.Options{BindAddress: "0"}})
	require.NoError(t, err)
	require.NoError(t, newNoteReconciler(newFakeLedgerStore(), false, 20).SetupWithManager(mgr))
	journal := &controllers.JournalReconciler{
		Client: k8sClient, Clock: fakeClock{t: time.Now()},
		Recorder: kube.NewEventRecorder(record.NewFakeRecorder(8)), Metrics: metrics.NewPrometheus(),
	}
	require.NoError(t, journal.SetupWithManager(mgr))
}

func TestRealClockNow(t *testing.T) {
	require.WithinDuration(t, time.Now(), kube.RealClock{}.Now(), 5*time.Second)
}
