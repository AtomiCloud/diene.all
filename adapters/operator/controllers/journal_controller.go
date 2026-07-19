package controllers

import (
	"context"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"

	"github.com/AtomiCloud/diene.go-base/adapters/operator/kube"
	"github.com/AtomiCloud/diene.go-base/adapters/operator/metrics"
	apiv1alpha1 "github.com/AtomiCloud/diene.go-base/api/v1alpha1"
	"github.com/AtomiCloud/diene.go-base/lib/operator/reconcile"
)

const journalController = "journal"

// JournalReconciler reconciles a Journal. It is the deliberately minimal second
// controller proving independent per-controller registration and the shared
// condition vocabulary; it owns no external resource and no ledger entry.
type JournalReconciler struct {
	client.Client
	Clock    kube.Clock
	Recorder kube.Recorder
	Metrics  metrics.Recorder
}

// +kubebuilder:rbac:groups=sample.diene.atomi.cloud,resources=journals,verbs=get;list;watch
// +kubebuilder:rbac:groups=sample.diene.atomi.cloud,resources=journals/status,verbs=get;update;patch

// Reconcile marks a Journal Ready.
func (r *JournalReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	r.Metrics.Tick(journalController)

	var journal apiv1alpha1.Journal
	if err := r.Get(ctx, req.NamespacedName, &journal); err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}

	journal.Status.ObservedGeneration = journal.Generation
	applyCondition(&journal.Status.Conditions, reconcile.Condition{
		Type:    reconcile.TypeReady,
		Status:  reconcile.StatusTrue,
		Reason:  "Recorded",
		Message: "journal entry recorded",
	}, journal.Generation, metav1.NewTime(r.Clock.Now()))
	r.Metrics.Observe(journalController, journal.Status.Conditions)
	r.Recorder.Event(&journal, reconcile.EventNormal, "Recorded", "journal entry recorded")
	return ctrl.Result{}, r.Status().Update(ctx, &journal)
}

// SetupWithManager registers the Journal controller with the manager.
func (r *JournalReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&apiv1alpha1.Journal{}).
		Named(journalController).
		Complete(r)
}
