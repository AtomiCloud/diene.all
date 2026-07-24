package controllers

import (
	"context"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"

	"github.com/AtomiCloud/diene.go-base/adapters/operator/kube"
	"github.com/AtomiCloud/diene.go-base/adapters/operator/metrics"
	apiv1alpha1 "github.com/AtomiCloud/diene.go-base/api/v1alpha1"
	"github.com/AtomiCloud/diene.go-base/lib/operator/ledger"
	"github.com/AtomiCloud/diene.go-base/lib/operator/reconcile"
)

// NoteOwnerLabel decorates the owned ConfigMap set for observability. Ownership
// decisions use the controller OwnerReference UID, never this label.
const NoteOwnerLabel = "operator-template.diene.atomi.cloud/note"

const noteController = "note"

// NoteReconciler reconciles a Note. It is thin: it maps API input, invokes the
// pure reconcile service, executes the returned plan through the ports, and flips
// Kubernetes status, events, and metrics. It carries no domain decisions.
type NoteReconciler struct {
	client.Client
	Clock      kube.Clock
	Recorder   kube.Recorder
	ConfigMaps kube.ConfigMapPort
	Ledger     ledger.Service
	Metrics    metrics.Recorder

	// Observe selects read-only mode. BrakeCap is the destructive-write cap.
	Observe  bool
	BrakeCap int
	// Platform and Landscape scope the ledger coordinate per instance.
	Platform  string
	Landscape string
}

// +kubebuilder:rbac:groups=sample.diene.atomi.cloud,resources=notes,verbs=get;list;watch;update
// +kubebuilder:rbac:groups=sample.diene.atomi.cloud,resources=notes/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=sample.diene.atomi.cloud,resources=notes/finalizers,verbs=update
// +kubebuilder:rbac:groups="",resources=configmaps,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups="",resources=events,verbs=create;patch
// +kubebuilder:rbac:groups=authentication.k8s.io,resources=tokenreviews,verbs=create
// +kubebuilder:rbac:groups=authorization.k8s.io,resources=subjectaccessreviews,verbs=create
// +kubebuilder:rbac:groups=coordination.k8s.io,resources=leases,verbs=get;create;update

// Reconcile drives a Note toward its desired state.
func (r *NoteReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	r.Metrics.Tick(noteController)

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
	spec := reconcile.Spec{
		Title:    note.Spec.Title,
		Body:     note.Spec.Body,
		Category: note.Spec.Category,
		Replicas: note.Spec.Replicas,
	}
	desiredNames := reconcile.DesiredNames(note.Name, spec)

	owned, foreign, err := r.ConfigMaps.ListOwned(ctx, note, desiredNames)
	if err != nil {
		return ctrl.Result{}, err
	}

	coord := r.coordinate(note.Name)
	entry, exists, gerr := r.Ledger.Get(ctx, coord)
	if gerr != nil {
		return r.ledgerUnavailable(ctx, note, gerr)
	}

	dec := reconcile.Decide(reconcile.Input{
		Owner:    note.Name,
		Spec:     spec,
		Existing: toOwned(owned),
		Foreign:  foreign,
		Ledger:   reconcile.LedgerState{Exists: exists, Phase: entry.Phase},
		Observe:  r.Observe,
		BrakeCap: r.BrakeCap,
	})

	if dec.Write {
		if lerr := r.applyLedgerPre(ctx, coord, note.Name, dec.LedgerPre); lerr != nil {
			return r.ledgerUnavailable(ctx, note, lerr)
		}
		for _, u := range dec.Upserts {
			if err := r.ConfigMaps.Upsert(ctx, note, u.Name, u.Payload); err != nil {
				return ctrl.Result{}, err
			}
		}
		for _, name := range dec.Deletes {
			if err := r.ConfigMaps.Delete(ctx, note, name); err != nil {
				return ctrl.Result{}, err
			}
		}
		if dec.ConfirmAfter {
			ref, cerr := r.confirmLedger(ctx, coord)
			if cerr != nil {
				// Writes already applied: publish the freshly applied count, not the
				// stale pre-write status value, before flipping WaitingForEndpoint.
				note.Status.OwnedConfigMaps = dec.OwnedCount
				return r.ledgerUnavailable(ctx, note, cerr)
			}
			note.Status.LedgerRef = ref
		}
	}

	r.publish(note, dec.OwnedCount, dec.Conditions, dec.Events)
	return ctrl.Result{}, r.Status().Update(ctx, note)
}

func (r *NoteReconciler) applyLedgerPre(ctx context.Context, coord ledger.Coordinate, name string, pre reconcile.LedgerPre) error {
	switch pre {
	case reconcile.LedgerPreIntent:
		_, err := r.Ledger.Intent(ctx, coord, name, "secret/notes/"+name)
		return err
	case reconcile.LedgerPreAdopt:
		_, err := r.Ledger.Adopt(ctx, coord)
		return err
	default:
		return nil
	}
}

func (r *NoteReconciler) confirmLedger(ctx context.Context, coord ledger.Coordinate) (string, error) {
	if _, err := r.Ledger.Created(ctx, coord); err != nil {
		return "", err
	}
	entry, err := r.Ledger.Confirm(ctx, coord)
	if err != nil {
		return "", err
	}
	return entry.Coordinate.Key(), nil
}

// ledgerUnavailable records a durable-ledger failure, flips WaitingForEndpoint,
// and requeues.
func (r *NoteReconciler) ledgerUnavailable(ctx context.Context, note *apiv1alpha1.Note, cause error) (ctrl.Result, error) {
	r.Metrics.LedgerFailure(noteController)
	r.publish(note, note.Status.OwnedConfigMaps,
		[]reconcile.Condition{reconcile.WaitingForEndpoint(cause.Error())},
		[]reconcile.Event{{Type: reconcile.EventWarning, Reason: "WaitingForEndpoint", Message: cause.Error()}})
	_ = r.Status().Update(ctx, note)
	return ctrl.Result{}, cause
}

func (r *NoteReconciler) publish(note *apiv1alpha1.Note, ownedCount int32, conditions []reconcile.Condition, events []reconcile.Event) {
	now := metav1.NewTime(r.Clock.Now())
	for _, c := range conditions {
		applyCondition(&note.Status.Conditions, c, note.Generation, now)
	}
	note.Status.OwnedConfigMaps = ownedCount
	note.Status.ObservedGeneration = note.Generation
	r.Metrics.Observe(noteController, note.Status.Conditions)
	for _, e := range events {
		r.Recorder.Event(note, e.Type, e.Reason, e.Message)
	}
}

func (r *NoteReconciler) finalize(ctx context.Context, note *apiv1alpha1.Note) (ctrl.Result, error) {
	if !controllerutil.ContainsFinalizer(note, apiv1alpha1.NoteFinalizer) {
		return ctrl.Result{}, nil
	}
	owned, _, err := r.ConfigMaps.ListOwned(ctx, note, nil)
	if err != nil {
		return ctrl.Result{}, err
	}
	for _, o := range owned {
		if err := r.ConfigMaps.Delete(ctx, note, o.Name); err != nil {
			return ctrl.Result{}, err
		}
	}
	if err := r.Ledger.Orphan(ctx, r.coordinate(note.Name)); err != nil {
		r.Metrics.LedgerFailure(noteController)
		return ctrl.Result{}, err
	}
	controllerutil.RemoveFinalizer(note, apiv1alpha1.NoteFinalizer)
	return ctrl.Result{}, r.Update(ctx, note)
}

func (r *NoteReconciler) coordinate(name string) ledger.Coordinate {
	return ledger.Coordinate{Platform: r.Platform, Landscape: r.Landscape, Class: noteController, Module: name}
}

func toOwned(cms []kube.OwnedConfigMap) []reconcile.Owned {
	out := make([]reconcile.Owned, 0, len(cms))
	for _, cm := range cms {
		out = append(out, reconcile.Owned{Name: cm.Name, Payload: cm.Payload})
	}
	return out
}

// SetupWithManager registers the Note controller with the manager.
func (r *NoteReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&apiv1alpha1.Note{}).
		Owns(&corev1.ConfigMap{}).
		Named(noteController).
		Complete(r)
}
