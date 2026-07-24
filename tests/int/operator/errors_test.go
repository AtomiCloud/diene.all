package operator_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/tools/record"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"

	"github.com/AtomiCloud/diene.go-base/adapters/operator/controllers"
	"github.com/AtomiCloud/diene.go-base/adapters/operator/kube"
	"github.com/AtomiCloud/diene.go-base/adapters/operator/metrics"
	"github.com/AtomiCloud/diene.go-base/lib/operator/ledger"
)

// These tests inject failing ports to exercise controller error-handling branches
// a real apiserver cannot deterministically produce. The kube/ledgerstore adapters
// themselves run against real dependencies (envtest + testcontainers) elsewhere.

type failingLedgerStore struct{}

func (failingLedgerStore) Get(context.Context, string) (ledger.Entry, bool, error) {
	return ledger.Entry{}, false, errors.New("ledger endpoint unreachable")
}

func (failingLedgerStore) Put(context.Context, ledger.Entry) error {
	return errors.New("ledger endpoint unreachable")
}

type putFailLedgerStore struct {
	present bool
	phase   ledger.Phase
}

func (s putFailLedgerStore) Get(context.Context, string) (ledger.Entry, bool, error) {
	return ledger.Entry{Phase: s.phase}, s.present, nil
}
func (putFailLedgerStore) Put(context.Context, ledger.Entry) error { return errors.New("put boom") }

type stubConfigMaps struct {
	owned     []kube.OwnedConfigMap
	foreign   []string
	listErr   error
	upsertErr error
	deleteErr error
}

func (s stubConfigMaps) ListOwned(context.Context, client.Object, []string) ([]kube.OwnedConfigMap, []string, error) {
	return s.owned, s.foreign, s.listErr
}

func (s stubConfigMaps) Upsert(context.Context, client.Object, string, string) error {
	return s.upsertErr
}

func (s stubConfigMaps) Delete(context.Context, client.Object, string) error { return s.deleteErr }

func reconcilerWith(cms kube.ConfigMapPort, store ledger.Store) *controllers.NoteReconciler {
	return &controllers.NoteReconciler{
		Client:     k8sClient,
		Clock:      fakeClock{t: time.Unix(1700000000, 0).UTC()},
		Recorder:   kube.NewEventRecorder(record.NewFakeRecorder(16)),
		ConfigMaps: cms,
		Ledger:     ledger.NewService(store),
		Metrics:    metrics.NewPrometheus(),
		BrakeCap:   100,
		Platform:   "diene",
		Landscape:  "lapras",
	}
}

func finalizedNote(t *testing.T, name string) {
	t.Helper()
	makeNote(t, name, "work", 1)
	reconcileNote(t, newNoteReconciler(newFakeLedgerStore(), false, 20), name, 2)
}

func request(name string) ctrl.Request {
	return ctrl.Request{NamespacedName: client.ObjectKey{Namespace: "default", Name: name}}
}

func TestConvergeListError(t *testing.T) {
	finalizedNote(t, "err-list")
	r := reconcilerWith(stubConfigMaps{listErr: errors.New("list boom")}, newFakeLedgerStore())
	_, err := r.Reconcile(context.Background(), request("err-list"))
	require.Error(t, err)
}

func TestConvergeUpsertError(t *testing.T) {
	finalizedNote(t, "err-upsert")
	r := reconcilerWith(stubConfigMaps{upsertErr: errors.New("upsert boom")}, newFakeLedgerStore())
	_, err := r.Reconcile(context.Background(), request("err-upsert"))
	require.Error(t, err)
}

func TestConvergeIntentError(t *testing.T) {
	finalizedNote(t, "err-intent")
	r := reconcilerWith(stubConfigMaps{}, putFailLedgerStore{present: false})
	_, err := r.Reconcile(context.Background(), request("err-intent"))
	require.Error(t, err)
}

func TestConvergeAdoptError(t *testing.T) {
	finalizedNote(t, "err-adopt")
	r := reconcilerWith(stubConfigMaps{}, putFailLedgerStore{present: true, phase: ledger.PhaseOrphaned})
	_, err := r.Reconcile(context.Background(), request("err-adopt"))
	require.Error(t, err)
}

func TestConvergeConfirmError(t *testing.T) {
	finalizedNote(t, "err-confirm")
	r := reconcilerWith(stubConfigMaps{}, putFailLedgerStore{present: true, phase: ledger.PhaseCreated})
	_, err := r.Reconcile(context.Background(), request("err-confirm"))
	require.Error(t, err)
}

func TestConvergeConfirmErrorPublishesAppliedCount(t *testing.T) {
	// The Note converges once (owned=1), then its replicas grow to 3 and the
	// confirm-after-write ledger transition fails. The published count must be the
	// freshly applied 3 (dec.OwnedCount), not the stale pre-write status value of 1.
	finalizedNote(t, "err-confirm-count")
	require.Equal(t, int32(1), getNote(t, "err-confirm-count").Status.OwnedConfigMaps)

	current := getNote(t, "err-confirm-count")
	current.Spec.Replicas = 3
	require.NoError(t, k8sClient.Update(context.Background(), current))

	// Ledger present + created so the reconcile writes then fails only at confirm.
	r := reconcilerWith(stubConfigMaps{}, putFailLedgerStore{present: true, phase: ledger.PhaseCreated})
	_, err := r.Reconcile(context.Background(), request("err-confirm-count"))
	require.Error(t, err)
	require.Equal(t, int32(3), getNote(t, "err-confirm-count").Status.OwnedConfigMaps)
}

func TestConvergeCreatedError(t *testing.T) {
	finalizedNote(t, "err-created")
	// Phase intent + a failing Put makes the intent->created transition error.
	r := reconcilerWith(stubConfigMaps{}, putFailLedgerStore{present: true, phase: ledger.PhaseIntent})
	_, err := r.Reconcile(context.Background(), request("err-created"))
	require.Error(t, err)
}

func TestConvergeGetLedgerError(t *testing.T) {
	finalizedNote(t, "err-get")
	r := reconcilerWith(stubConfigMaps{}, failingLedgerStore{})
	_, err := r.Reconcile(context.Background(), request("err-get"))
	require.Error(t, err)
	waiting := metav1.Condition{}
	for _, c := range getNote(t, "err-get").Status.Conditions {
		if c.Type == "WaitingForEndpoint" {
			waiting = c
		}
	}
	require.Equal(t, metav1.ConditionTrue, waiting.Status)
}

func TestConvergeDeleteError(t *testing.T) {
	finalizedNote(t, "err-delete")
	// One owned copy outside the desired set forces a delete that the stub fails.
	r := reconcilerWith(stubConfigMaps{owned: []kube.OwnedConfigMap{{Name: "err-delete-copy-9"}}, deleteErr: errors.New("del boom")}, newFakeLedgerStore())
	_, err := r.Reconcile(context.Background(), request("err-delete"))
	require.Error(t, err)
}

func TestFinalizeListError(t *testing.T) {
	finalizedNote(t, "err-fin-list")
	require.NoError(t, k8sClient.Delete(context.Background(), getNote(t, "err-fin-list")))
	r := reconcilerWith(stubConfigMaps{listErr: errors.New("list boom")}, newFakeLedgerStore())
	_, err := r.Reconcile(context.Background(), request("err-fin-list"))
	require.Error(t, err)
}

func TestFinalizeDeleteError(t *testing.T) {
	finalizedNote(t, "err-fin-del")
	require.NoError(t, k8sClient.Delete(context.Background(), getNote(t, "err-fin-del")))
	r := reconcilerWith(stubConfigMaps{owned: []kube.OwnedConfigMap{{Name: "err-fin-del-copy-0"}}, deleteErr: errors.New("del boom")}, newFakeLedgerStore())
	_, err := r.Reconcile(context.Background(), request("err-fin-del"))
	require.Error(t, err)
}

func TestFinalizeOrphanError(t *testing.T) {
	finalizedNote(t, "err-fin-orphan")
	require.NoError(t, k8sClient.Delete(context.Background(), getNote(t, "err-fin-orphan")))
	r := reconcilerWith(stubConfigMaps{}, failingLedgerStore{})
	_, err := r.Reconcile(context.Background(), request("err-fin-orphan"))
	require.Error(t, err)
}
