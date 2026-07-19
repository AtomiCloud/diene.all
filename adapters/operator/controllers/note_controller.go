package controllers

import (
	"context"
	"fmt"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"

	"github.com/AtomiCloud/diene.go-base/adapters/operator/kube"
	apiv1alpha1 "github.com/AtomiCloud/diene.go-base/api/v1alpha1"
	"github.com/AtomiCloud/diene.go-base/lib/operator/brake"
	"github.com/AtomiCloud/diene.go-base/lib/operator/ledger"
	libnote "github.com/AtomiCloud/diene.go-base/lib/operator/note"
	"github.com/AtomiCloud/diene.go-base/lib/operator/plan"
)

// NoteOwnerLabel marks the owned ConfigMap set of a Note.
const NoteOwnerLabel = "operator-template.diene.atomi.cloud/note"

// NoteReconciler reconciles a Note. It is thin: it delegates every decision to
// the pure lib services and every k8s resource operation to the kube ports, and
// only flips the standard condition vocabulary from their outputs.
type NoteReconciler struct {
	client.Client
	Clock      kube.Clock
	Recorder   kube.Recorder
	ConfigMaps kube.ConfigMapPort
	Ledger     ledger.Service

	// Observe selects the read-only upgrade-safety mode (no provider writes).
	Observe bool
	// BrakeCap is the destructive-write percentage-per-tick cap (0..100).
	BrakeCap int
	// Platform and Landscape scope the ledger coordinate per instance.
	Platform  string
	Landscape string
}

// +kubebuilder:rbac:groups=sample.diene.atomi.cloud,resources=notes,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=sample.diene.atomi.cloud,resources=notes/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=sample.diene.atomi.cloud,resources=notes/finalizers,verbs=update
// +kubebuilder:rbac:groups="",resources=configmaps,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups="",resources=events,verbs=create;patch

// Reconcile drives a Note toward its desired state.
func (r *NoteReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	var note apiv1alpha1.Note
	if err := r.Get(ctx, req.NamespacedName, &note); err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}

	if !note.DeletionTimestamp.IsZero() {
		return r.finalize(ctx, &note)
	}

	if controllerutil.AddFinalizer(&note, apiv1alpha1.NoteFinalizer) {
		return ctrl.Result{}, r.Update(ctx, &note)
	}

	return r.converge(ctx, &note)
}

func (r *NoteReconciler) converge(ctx context.Context, note *apiv1alpha1.Note) (ctrl.Result, error) {
	spec := libnote.Spec{
		Title:    note.Spec.Title,
		Body:     note.Spec.Body,
		Category: note.Spec.Category,
		Replicas: note.Spec.Replicas,
	}
	desired := libnote.DesiredCopies(note.Name, spec)

	existing, err := r.ConfigMaps.List(ctx, note.Namespace, note.Name)
	if err != nil {
		return ctrl.Result{}, err
	}
	pl := plan.Diff(desired, existing)

	if decision := brake.Evaluate(len(existing), len(pl.Deletes), r.BrakeCap); decision.Tripped {
		r.Recorder.Event(note, corev1.EventTypeWarning, "BlastBrakeTripped", decision.Message)
		r.setCondition(note, libnote.BrakeCondition(decision.Message))
		return ctrl.Result{}, r.Status().Update(ctx, note)
	}

	if r.Observe {
		r.setCondition(note, observeCondition(pl))
		return ctrl.Result{}, r.Status().Update(ctx, note)
	}

	coord := r.coordinate(note.Name)
	entry, err := r.Ledger.Reserve(ctx, coord, note.Name, "secret/notes/"+note.Name)
	if err != nil {
		return ctrl.Result{}, err
	}

	if err := r.applyPlan(ctx, note, spec, pl); err != nil {
		return r.reportConflict(ctx, note, err)
	}
	if _, _, err := r.Ledger.Advance(ctx, coord); err != nil {
		return ctrl.Result{}, err
	}

	note.Status.OwnedConfigMaps = note.Spec.Replicas
	note.Status.ObservedGeneration = note.Generation
	note.Status.LedgerRef = entry.Coordinate.Key()
	r.setCondition(note, libnote.ReadyCondition(len(desired), len(desired)))
	r.Recorder.Event(note, corev1.EventTypeNormal, "Converged", "note converged to Ready")
	return ctrl.Result{}, r.Status().Update(ctx, note)
}

func (r *NoteReconciler) finalize(ctx context.Context, note *apiv1alpha1.Note) (ctrl.Result, error) {
	if !controllerutil.ContainsFinalizer(note, apiv1alpha1.NoteFinalizer) {
		return ctrl.Result{}, nil
	}
	existing, err := r.ConfigMaps.List(ctx, note.Namespace, note.Name)
	if err != nil {
		return ctrl.Result{}, err
	}
	for _, name := range existing {
		if err := r.ConfigMaps.Delete(ctx, note.Namespace, name); err != nil {
			return ctrl.Result{}, err
		}
	}
	// Orphan the ledger entry; a finalizer never destroys the external record.
	if err := r.Ledger.Orphan(ctx, r.coordinate(note.Name)); err != nil {
		return ctrl.Result{}, err
	}
	controllerutil.RemoveFinalizer(note, apiv1alpha1.NoteFinalizer)
	return ctrl.Result{}, r.Update(ctx, note)
}

func (r *NoteReconciler) applyPlan(ctx context.Context, note *apiv1alpha1.Note, spec libnote.Spec, pl plan.Plan) error {
	for _, name := range pl.Creates {
		if err := r.ConfigMaps.Ensure(ctx, note, name, libnote.Payload(spec)); err != nil {
			return err
		}
	}
	for _, name := range pl.Deletes {
		if err := r.ConfigMaps.Delete(ctx, note.Namespace, name); err != nil {
			return err
		}
	}
	return nil
}

func (r *NoteReconciler) reportConflict(ctx context.Context, note *apiv1alpha1.Note, applyErr error) (ctrl.Result, error) {
	if !apierrors.IsAlreadyExists(applyErr) {
		return ctrl.Result{}, applyErr
	}
	r.Recorder.Event(note, corev1.EventTypeWarning, "OwnedNameCollision", applyErr.Error())
	r.setCondition(note, plan.Condition{
		Type:    plan.TypeConflict,
		Status:  plan.StatusTrue,
		Reason:  "OwnedNameCollision",
		Message: applyErr.Error(),
	})
	return ctrl.Result{}, r.Status().Update(ctx, note)
}

func (r *NoteReconciler) setCondition(note *apiv1alpha1.Note, c plan.Condition) {
	applyCondition(&note.Status.Conditions, c, note.Generation, metav1.NewTime(r.Clock.Now()))
}

func (r *NoteReconciler) coordinate(name string) ledger.Coordinate {
	return ledger.Coordinate{Platform: r.Platform, Landscape: r.Landscape, Class: "note", Module: name}
}

func observeCondition(pl plan.Plan) plan.Condition {
	if pl.Empty() {
		return plan.Condition{
			Type:    plan.TypeDrifted,
			Status:  plan.StatusFalse,
			Reason:  "InSync",
			Message: "observe mode: healthy fleet, empty plan",
		}
	}
	return plan.Condition{
		Type:    plan.TypeDrifted,
		Status:  plan.StatusTrue,
		Reason:  "WouldApply",
		Message: fmt.Sprintf("observe mode: would create %d, delete %d (no writes)", len(pl.Creates), len(pl.Deletes)),
	}
}

// SetupWithManager registers the Note controller with the manager.
func (r *NoteReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&apiv1alpha1.Note{}).
		Owns(&corev1.ConfigMap{}).
		Named("note").
		Complete(r)
}
