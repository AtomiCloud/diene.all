package operator_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"k8s.io/client-go/tools/record"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"

	"github.com/AtomiCloud/diene.go-base/adapters/operator/controllers"
	"github.com/AtomiCloud/diene.go-base/adapters/operator/kube"
	apiv1alpha1 "github.com/AtomiCloud/diene.go-base/api/v1alpha1"
	"github.com/AtomiCloud/diene.go-base/lib/operator/ledger"
)

// These tests inject failing ports to exercise the controller's error-handling
// branches, which a real apiserver cannot deterministically produce. The kube
// and ledgerstore adapters themselves are exercised against real dependencies
// (envtest + testcontainers MinIO) elsewhere.

type stubConfigMaps struct {
	list      []string
	listErr   error
	ensureErr error
	deleteErr error
}

func (s stubConfigMaps) List(context.Context, string, string) ([]string, error) {
	return s.list, s.listErr
}

func (s stubConfigMaps) Ensure(context.Context, client.Object, string, string) error {
	return s.ensureErr
}
func (s stubConfigMaps) Delete(context.Context, string, string) error { return s.deleteErr }

type stubLedgerStore struct {
	getErr, putErr error
	present        bool
}

func (s stubLedgerStore) Get(context.Context, string) (ledger.Entry, bool, error) {
	return ledger.Entry{}, s.present, s.getErr
}
func (s stubLedgerStore) Put(context.Context, ledger.Entry) error { return s.putErr }

func reconcilerWith(cms kube.ConfigMapPort, store ledger.Store) *controllers.NoteReconciler {
	return &controllers.NoteReconciler{
		Client:     k8sClient,
		Clock:      fakeClock{t: time.Unix(1700000000, 0).UTC()},
		Recorder:   kube.NewEventRecorder(record.NewFakeRecorder(16)),
		ConfigMaps: cms,
		Ledger:     ledger.NewService(store),
		BrakeCap:   20,
		Platform:   "diene",
		Landscape:  "lapras",
	}
}

func finalizedNote(t *testing.T, name string) *apiv1alpha1.Note {
	t.Helper()
	note := makeNote(t, name, "work", 1)
	// Add the finalizer via a real converge so a later delete keeps the object.
	base := newNoteReconciler(newFakeLedgerStore(), false, 20)
	reconcileNote(t, base, note, 2)
	return getNote(t, name)
}

func request(name string) ctrl.Request {
	return ctrl.Request{NamespacedName: client.ObjectKey{Namespace: "default", Name: name}}
}

func TestConvergeListError(t *testing.T) {
	note := finalizedNote(t, "err-list")
	r := reconcilerWith(stubConfigMaps{listErr: errors.New("list boom")}, newFakeLedgerStore())
	_, err := r.Reconcile(context.Background(), request(note.Name))
	require.Error(t, err)
}

func TestConvergeReserveError(t *testing.T) {
	note := finalizedNote(t, "err-reserve")
	r := reconcilerWith(stubConfigMaps{}, stubLedgerStore{getErr: errors.New("reserve boom")})
	_, err := r.Reconcile(context.Background(), request(note.Name))
	require.Error(t, err)
}

func TestConvergeAdvanceError(t *testing.T) {
	note := finalizedNote(t, "err-advance")
	// Reserve returns an existing entry (no put), then Advance's Put fails.
	r := reconcilerWith(stubConfigMaps{}, stubLedgerStore{present: true, putErr: errors.New("advance boom")})
	_, err := r.Reconcile(context.Background(), request(note.Name))
	require.Error(t, err)
}

func TestApplyPlanEnsureGenericError(t *testing.T) {
	note := finalizedNote(t, "err-ensure")
	r := reconcilerWith(stubConfigMaps{ensureErr: errors.New("ensure boom")}, newFakeLedgerStore())
	_, err := r.Reconcile(context.Background(), request(note.Name))
	require.Error(t, err, "a non-AlreadyExists ensure error must propagate")
}

func TestFinalizeListError(t *testing.T) {
	note := finalizedNote(t, "err-finalize-list")
	require.NoError(t, k8sClient.Delete(context.Background(), note))
	r := reconcilerWith(stubConfigMaps{listErr: errors.New("list boom")}, newFakeLedgerStore())
	_, err := r.Reconcile(context.Background(), request(note.Name))
	require.Error(t, err)
}

func TestFinalizeDeleteError(t *testing.T) {
	note := finalizedNote(t, "err-finalize-del")
	require.NoError(t, k8sClient.Delete(context.Background(), note))
	r := reconcilerWith(stubConfigMaps{list: []string{"err-finalize-del-copy-0"}, deleteErr: errors.New("del boom")}, newFakeLedgerStore())
	_, err := r.Reconcile(context.Background(), request(note.Name))
	require.Error(t, err)
}

func TestFinalizeOrphanError(t *testing.T) {
	note := finalizedNote(t, "err-finalize-orphan")
	require.NoError(t, k8sClient.Delete(context.Background(), note))
	r := reconcilerWith(stubConfigMaps{}, stubLedgerStore{getErr: errors.New("orphan boom")})
	_, err := r.Reconcile(context.Background(), request(note.Name))
	require.Error(t, err)
}

func TestFinalizeAlreadyGoneIsNoOp(t *testing.T) {
	// A note without our finalizer that is being deleted: finalize is a no-op.
	note := makeNote(t, "no-finalizer", "work", 1)
	require.NoError(t, k8sClient.Delete(context.Background(), note))
	r := reconcilerWith(stubConfigMaps{}, newFakeLedgerStore())
	_, err := r.Reconcile(context.Background(), request(note.Name))
	require.NoError(t, err)
}
