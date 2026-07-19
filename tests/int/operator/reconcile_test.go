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
	apiv1alpha1 "github.com/AtomiCloud/diene.go-base/api/v1alpha1"
	"github.com/AtomiCloud/diene.go-base/lib/operator/ledger"
	"github.com/AtomiCloud/diene.go-base/lib/operator/plan"
)

// fakeLedgerStore is an in-memory ledger.Store used by the envtest reconcile
// tests so they run without Docker. The MinIO adapter itself is covered by
// ledger_minio_test.go against a real testcontainers backend.
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
		Observe:    observe,
		BrakeCap:   brakeCap,
		Platform:   "diene",
		Landscape:  "lapras",
	}
}

func reconcileNote(t *testing.T, r *controllers.NoteReconciler, note *apiv1alpha1.Note, times int) {
	t.Helper()
	key := client.ObjectKeyFromObject(note)
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

func makeNote(t *testing.T, name, category string, replicas int32) *apiv1alpha1.Note {
	t.Helper()
	note := &apiv1alpha1.Note{
		ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: "default"},
		Spec:       apiv1alpha1.NoteSpec{Title: "Title " + name, Body: "body", Category: category, Replicas: replicas},
	}
	require.NoError(t, k8sClient.Create(context.Background(), note))
	return note
}

func TestNoteConvergesToReady(t *testing.T) {
	r := newNoteReconciler(newFakeLedgerStore(), false, 20)
	note := makeNote(t, "converge", "work", 2)
	reconcileNote(t, r, note, 2) // add finalizer, then converge

	got := getNote(t, "converge")
	require.Equal(t, int32(2), got.Status.OwnedConfigMaps)
	require.Equal(t, "diene/lapras/note/converge", got.Status.LedgerRef)
	ready := apimeta.FindStatusCondition(got.Status.Conditions, plan.TypeReady)
	require.NotNil(t, ready)
	require.Equal(t, metav1.ConditionTrue, ready.Status)
	require.Equal(t, int64(1700000000), ready.LastTransitionTime.Unix())

	var cms corev1.ConfigMapList
	require.NoError(t, k8sClient.List(context.Background(), &cms, client.InNamespace("default"), client.MatchingLabels{controllers.NoteOwnerLabel: "converge"}))
	require.Len(t, cms.Items, 2)
}

func TestNoteFinalizerLifecycle(t *testing.T) {
	store := newFakeLedgerStore()
	r := newNoteReconciler(store, false, 20)
	note := makeNote(t, "finalized", "personal", 1)
	reconcileNote(t, r, note, 2)
	require.Contains(t, getNote(t, "finalized").Finalizers, apiv1alpha1.NoteFinalizer)

	require.NoError(t, k8sClient.Delete(context.Background(), getNote(t, "finalized")))
	reconcileNote(t, r, note, 1) // finalize: delete copies, orphan ledger, remove finalizer

	var note2 apiv1alpha1.Note
	err := k8sClient.Get(context.Background(), client.ObjectKey{Namespace: "default", Name: "finalized"}, &note2)
	require.True(t, client.IgnoreNotFound(err) == nil && err != nil, "note should be gone after finalizer removal")

	entry, ok, _ := store.Get(context.Background(), "diene/lapras/note/finalized")
	require.True(t, ok)
	require.Equal(t, ledger.PhaseOrphaned, entry.Phase)
}

func TestNoteObserveWouldApply(t *testing.T) {
	r := newNoteReconciler(newFakeLedgerStore(), true, 20)
	note := makeNote(t, "observe-drift", "work", 2)
	reconcileNote(t, r, note, 2)

	got := getNote(t, "observe-drift")
	drifted := apimeta.FindStatusCondition(got.Status.Conditions, plan.TypeDrifted)
	require.NotNil(t, drifted)
	require.Equal(t, metav1.ConditionTrue, drifted.Status)

	var cms corev1.ConfigMapList
	require.NoError(t, k8sClient.List(context.Background(), &cms, client.InNamespace("default"), client.MatchingLabels{controllers.NoteOwnerLabel: "observe-drift"}))
	require.Empty(t, cms.Items, "observe mode must not write")
}

func TestNoteObserveInSync(t *testing.T) {
	store := newFakeLedgerStore()
	active := newNoteReconciler(store, false, 20)
	note := makeNote(t, "observe-sync", "archive", 1)
	reconcileNote(t, active, note, 2) // converge: create copy-0

	// A healthy fleet observed produces an empty plan (Drifted=False).
	observe := newNoteReconciler(store, true, 20)
	reconcileNote(t, observe, note, 1)

	drifted := apimeta.FindStatusCondition(getNote(t, "observe-sync").Status.Conditions, plan.TypeDrifted)
	require.NotNil(t, drifted)
	require.Equal(t, metav1.ConditionFalse, drifted.Status)
}

func TestNoteBlastBrakeTrips(t *testing.T) {
	r := newNoteReconciler(newFakeLedgerStore(), false, 20)
	note := makeNote(t, "brake", "work", 4)
	reconcileNote(t, r, note, 2)
	require.Equal(t, int32(4), getNote(t, "brake").Status.OwnedConfigMaps)

	// Shrink to one copy: deleting 3 of 4 (75%) exceeds the 20% cap and must trip.
	current := getNote(t, "brake")
	current.Spec.Replicas = 1
	require.NoError(t, k8sClient.Update(context.Background(), current))
	reconcileNote(t, r, current, 1)

	tripped := apimeta.FindStatusCondition(getNote(t, "brake").Status.Conditions, plan.TypeBlastBrakeTripped)
	require.NotNil(t, tripped)
	require.Equal(t, metav1.ConditionTrue, tripped.Status)

	var cms corev1.ConfigMapList
	require.NoError(t, k8sClient.List(context.Background(), &cms, client.InNamespace("default"), client.MatchingLabels{controllers.NoteOwnerLabel: "brake"}))
	require.Len(t, cms.Items, 4, "blast brake must write nothing")
}

func TestNoteConflictOnUnownedName(t *testing.T) {
	// Pre-create an unowned ConfigMap occupying the desired copy-0 name.
	blocker := &corev1.ConfigMap{ObjectMeta: metav1.ObjectMeta{Name: "conflict-copy-0", Namespace: "default"}}
	require.NoError(t, k8sClient.Create(context.Background(), blocker))

	r := newNoteReconciler(newFakeLedgerStore(), false, 20)
	note := makeNote(t, "conflict", "work", 1)
	reconcileNote(t, r, note, 2)

	conflict := apimeta.FindStatusCondition(getNote(t, "conflict").Status.Conditions, plan.TypeConflict)
	require.NotNil(t, conflict)
	require.Equal(t, metav1.ConditionTrue, conflict.Status)
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
	}
	_, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: client.ObjectKeyFromObject(journal)})
	require.NoError(t, err)

	var got apiv1alpha1.Journal
	require.NoError(t, k8sClient.Get(context.Background(), client.ObjectKeyFromObject(journal), &got))
	ready := apimeta.FindStatusCondition(got.Status.Conditions, plan.TypeReady)
	require.NotNil(t, ready)
	require.Equal(t, metav1.ConditionTrue, ready.Status)
}

func TestInvalidNoteRejectedBySchema(t *testing.T) {
	invalid := &apiv1alpha1.Note{
		ObjectMeta: metav1.ObjectMeta{Name: "invalid", Namespace: "default"},
		Spec:       apiv1alpha1.NoteSpec{Title: "t", Body: "b", Category: "nonsense", Replicas: 1},
	}
	err := k8sClient.Create(context.Background(), invalid)
	require.Error(t, err, "category outside the enum must be rejected by the generated CRD schema")
}

func TestMultiControllerWiring(t *testing.T) {
	mgr, err := manager.New(restConfig, manager.Options{Scheme: testScheme, Metrics: metricsserver.Options{BindAddress: "0"}})
	require.NoError(t, err)

	note := newNoteReconciler(newFakeLedgerStore(), false, 20)
	require.NoError(t, note.SetupWithManager(mgr))
	journal := &controllers.JournalReconciler{
		Client:   k8sClient,
		Clock:    fakeClock{t: time.Now()},
		Recorder: kube.NewEventRecorder(record.NewFakeRecorder(8)),
	}
	require.NoError(t, journal.SetupWithManager(mgr))
}

func TestRealClockNow(t *testing.T) {
	require.WithinDuration(t, time.Now(), kube.RealClock{}.Now(), 5*time.Second)
}
