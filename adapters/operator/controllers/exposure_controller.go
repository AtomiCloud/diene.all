package controllers

import (
	"context"
	"errors"

	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/handler"

	"github.com/AtomiCloud/diene.boron/adapters/operator/cloudflare"
	"github.com/AtomiCloud/diene.boron/adapters/operator/kube"
	"github.com/AtomiCloud/diene.boron/adapters/operator/metrics"
	apiv1alpha1 "github.com/AtomiCloud/diene.boron/api/v1alpha1"
	"github.com/AtomiCloud/diene.boron/lib/operator/reconcile"
)

const exposureController = "exposure"

// PublicServiceAnnotation marks a backend Service as also reachable via a
// public route (platinum); exposing it requires allowSharedBackend: true.
const PublicServiceAnnotation = "boron.atomi.cloud/public"

// ExposureReconciler reconciles an Exposure: 1 CR = 1 CF Access Application.
// It is thin: it resolves cluster and provider reads, invokes the pure
// reconcile service for every decision (admission, hostname derivation, TLS
// preflight, ref resolution, conflict determinism), and executes the returned
// all-or-nothing program through the provider port.
type ExposureReconciler struct {
	client.Client
	Clock    kube.Clock
	Recorder kube.Recorder
	Secrets  kube.SecretPort
	Services kube.ServicePort
	Provider cloudflare.Port
	Metrics  metrics.Recorder

	// Installation is the trusted Garden-supplied installation identity.
	Installation reconcile.Installation
}

// +kubebuilder:rbac:groups=boron.atomi.cloud,resources=exposures,verbs=get;list;watch;update
// +kubebuilder:rbac:groups=boron.atomi.cloud,resources=exposures/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=boron.atomi.cloud,resources=exposures/finalizers,verbs=update
// +kubebuilder:rbac:groups="",resources=services,verbs=get;list;watch

// Reconcile drives an Exposure toward its desired state.
func (r *ExposureReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	r.Metrics.Tick(exposureController)

	var exposure apiv1alpha1.Exposure
	if err := r.Get(ctx, req.NamespacedName, &exposure); err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}

	if !exposure.DeletionTimestamp.IsZero() {
		return r.finalize(ctx, &exposure)
	}
	if controllerutil.AddFinalizer(&exposure, apiv1alpha1.ExposureFinalizer) {
		return ctrl.Result{}, r.Update(ctx, &exposure)
	}
	return r.converge(ctx, &exposure)
}

// converge implements the goal's reconcile mechanics: gather every read the
// pure service needs, let DecideExposure order the gates, then execute the
// program (LIST-then-adopt, ordered policy attach, proxied CNAME) or nothing.
func (r *ExposureReconciler) converge(ctx context.Context, exposure *apiv1alpha1.Exposure) (ctrl.Result, error) {
	in := reconcile.ExposureInput{
		Installation: r.Installation,
		Coordinates: reconcile.Coordinates{
			Landscape: exposure.Spec.Coordinates.Landscape,
			Platform:  exposure.Spec.Coordinates.Platform,
			Service:   exposure.Spec.Coordinates.Service,
			Module:    exposure.Spec.Coordinates.Module,
		},
		Instance:           exposure.Spec.Instance,
		Path:               exposure.Spec.Path,
		Namespace:          exposure.Namespace,
		AllowSharedBackend: exposure.Spec.AllowSharedBackend,
		BackendName:        exposure.Spec.Backend.Name,
		BackendPort:        exposure.Spec.Backend.Port,
		PolicyNames:        exposure.Spec.Policies,
		Self: reconcile.ConflictCandidate{
			Namespace: exposure.Namespace,
			Name:      exposure.Name,
			CreatedAt: exposure.CreationTimestamp.Time,
		},
	}

	credentials, tunnel, err := r.resolveTunnel(ctx, exposure, &in)
	if err != nil {
		return ctrl.Result{}, err
	}

	if in.TunnelFound && in.AccountFound && in.AccountReady {
		if err = r.resolveProviderReads(ctx, credentials, exposure, &in); err != nil {
			return ctrl.Result{}, err
		}
		if err = r.resolveConflict(ctx, exposure, &in); err != nil {
			return ctrl.Result{}, err
		}
	}

	decision := reconcile.DecideExposure(in)
	exposure.Status.Hostname = decision.Hostname

	if decision.Program == nil {
		// Nothing programmed: clear any previously held route so a broken
		// Exposure never keeps a stale rule, and surface the refusal.
		exposure.Status.ProgrammedRule = apiv1alpha1.ProgrammedRule{}
		exposure.Status.AccessAppID = ""
		r.publish(exposure, decision)
		return ctrl.Result{}, r.Status().Update(ctx, exposure)
	}

	programmed := reconcile.ProgrammedCondition(true, "")
	adopted := false
	appID, adopted, perr := r.ensureAccessApplication(ctx, credentials, exposure, decision.Program)
	if perr != nil {
		programmed = reconcile.ProgrammedCondition(false, perr.Error())
	} else {
		exposure.Status.AccessAppID = appID
		target := tunnel.Status.TunnelID + ".cfargotunnel.com"
		if derr := r.Provider.UpsertProxiedCNAME(ctx, credentials, tunnel.Spec.Zone, decision.Program.Hostname, target); derr != nil {
			programmed = reconcile.ProgrammedCondition(false, derr.Error())
		} else {
			exposure.Status.ProgrammedRule = apiv1alpha1.ProgrammedRule{
				Hostname: decision.Program.Hostname,
				Path:     decision.Program.Path,
				Backend:  decision.Program.Backend,
			}
		}
	}

	decision.Conditions = append(decision.Conditions, programmed)
	if adopted {
		decision.Events = append(decision.Events, reconcile.Event{
			Type: reconcile.EventNormal, Reason: reconcile.ReasonAccessAppAdopted,
			Message: "adopted the pre-existing access application for the derived hostname",
		})
	}
	r.publish(exposure, decision)
	return ctrl.Result{}, r.Status().Update(ctx, exposure)
}

// ensureAccessApplication is the LIST-then-adopt-or-create path: find first and
// adopt; only create when absent; a duplicate-create 409 falls back to the same
// LIST-then-adopt path, never a hard error.
func (r *ExposureReconciler) ensureAccessApplication(ctx context.Context, credentials cloudflare.Credentials, exposure *apiv1alpha1.Exposure, program *reconcile.ExposureProgram) (string, bool, error) {
	desired := cloudflare.AccessApplication{
		Name:      exposure.Namespace + "-" + exposure.Name,
		Hostname:  program.Hostname,
		Path:      program.Path,
		PolicyIDs: program.PolicyIDs,
	}

	id, found, err := r.Provider.FindAccessApplication(ctx, credentials, program.Hostname, program.Path)
	if err != nil {
		return "", false, err
	}
	if found {
		return id, true, r.Provider.UpdateAccessApplication(ctx, credentials, id, desired)
	}

	id, err = r.Provider.CreateAccessApplication(ctx, credentials, desired)
	if errors.Is(err, cloudflare.ErrApplicationAlreadyExists) {
		// Duplicate-create race: fall back to the same LIST-then-adopt path.
		id, found, err = r.Provider.FindAccessApplication(ctx, credentials, program.Hostname, program.Path)
		if err != nil {
			return "", false, err
		}
		if !found {
			return "", false, errors.New("access application vanished between duplicate-create and adopt list")
		}
		return id, true, r.Provider.UpdateAccessApplication(ctx, credentials, id, desired)
	}
	if err != nil {
		return "", false, err
	}
	return id, false, nil
}

// resolveTunnel loads the Exposure's Tunnel, its Account, and credentials.
func (r *ExposureReconciler) resolveTunnel(ctx context.Context, exposure *apiv1alpha1.Exposure, in *reconcile.ExposureInput) (cloudflare.Credentials, *apiv1alpha1.Tunnel, error) {
	var tunnel apiv1alpha1.Tunnel
	err := r.Get(ctx, client.ObjectKey{Namespace: exposure.Namespace, Name: exposure.Spec.TunnelRef.Name}, &tunnel)
	if apierrors.IsNotFound(err) {
		return cloudflare.Credentials{}, nil, nil
	}
	if err != nil {
		return cloudflare.Credentials{}, nil, err
	}
	in.TunnelFound = true
	in.TunnelZone = tunnel.Spec.Zone
	in.TunnelID = tunnel.Status.TunnelID

	var account apiv1alpha1.Account
	err = r.Get(ctx, client.ObjectKey{Namespace: tunnel.Namespace, Name: tunnel.Spec.AccountRef.Name}, &account)
	if apierrors.IsNotFound(err) {
		return cloudflare.Credentials{}, &tunnel, nil
	}
	if err != nil {
		return cloudflare.Credentials{}, &tunnel, err
	}
	in.AccountFound = true
	in.AccountReady = conditionTrue(account.Status.Conditions, reconcile.TypeReady)
	if !in.AccountReady {
		return cloudflare.Credentials{}, &tunnel, nil
	}

	lookup, err := r.Secrets.ReadToken(ctx, account.Namespace, account.Spec.APITokenSecretRef.Name)
	if err != nil {
		return cloudflare.Credentials{}, &tunnel, err
	}
	if !lookup.SecretFound || !lookup.TokenPresent {
		in.AccountReady = false
		return cloudflare.Credentials{}, &tunnel, nil
	}
	return cloudflare.Credentials{AccountID: account.Spec.AccountID, APIToken: lookup.Token}, &tunnel, nil
}

// resolveProviderReads gathers the backend, TLS-coverage, and policy reads the
// pure service needs. The hostname used for the preflight is derived by the
// same pure function the service uses.
func (r *ExposureReconciler) resolveProviderReads(ctx context.Context, credentials cloudflare.Credentials, exposure *apiv1alpha1.Exposure, in *reconcile.ExposureInput) error {
	backend, err := r.Services.ReadBackend(ctx, exposure.Namespace, exposure.Spec.Backend.Name, exposure.Spec.Backend.Port, PublicServiceAnnotation)
	if err != nil {
		return err
	}
	in.BackendFound = backend.Found
	in.BackendPortFound = backend.PortFound
	in.BackendPublic = backend.Public

	hostname := reconcile.DeriveHostname(in.Coordinates, in.Instance, in.TunnelZone)
	coverage, err := r.Provider.CheckTLSCoverage(ctx, credentials, in.TunnelZone, hostname)
	if err != nil {
		in.TLSChecked = true
		in.TLSMessage = err.Error()
		return nil
	}
	in.TLSChecked = true
	in.TLSCovered = coverage.Covered
	in.TLSMessage = coverage.Message

	resolved, err := r.Provider.LookupPolicies(ctx, credentials, exposure.Spec.Policies)
	if err != nil {
		return err
	}
	in.ResolvedPolicy = resolved
	return nil
}

// resolveConflict finds the oldest rival Exposure claiming the same
// hostname+path (oldest-wins determinism happens in the pure service).
func (r *ExposureReconciler) resolveConflict(ctx context.Context, exposure *apiv1alpha1.Exposure, in *reconcile.ExposureInput) error {
	var list apiv1alpha1.ExposureList
	if err := r.List(ctx, &list); err != nil {
		return err
	}
	hostname := reconcile.DeriveHostname(in.Coordinates, in.Instance, in.TunnelZone)
	path := reconcile.NormalizePath(in.Path)
	for i := range list.Items {
		rival := &list.Items[i]
		if rival.Namespace == exposure.Namespace && rival.Name == exposure.Name {
			continue
		}
		if rival.Spec.TunnelRef.Name != exposure.Spec.TunnelRef.Name {
			continue
		}
		rivalHostname := reconcile.DeriveHostname(reconcile.Coordinates{
			Landscape: rival.Spec.Coordinates.Landscape,
			Platform:  rival.Spec.Coordinates.Platform,
			Service:   rival.Spec.Coordinates.Service,
			Module:    rival.Spec.Coordinates.Module,
		}, rival.Spec.Instance, in.TunnelZone)
		if rivalHostname != hostname || reconcile.NormalizePath(rival.Spec.Path) != path {
			continue
		}
		candidate := reconcile.ConflictCandidate{
			Namespace: rival.Namespace,
			Name:      rival.Name,
			CreatedAt: rival.CreationTimestamp.Time,
		}
		if !in.HasRival || reconcile.OlderCandidate(candidate, in.Oldest) {
			in.Oldest = candidate
			in.HasRival = true
		}
	}
	return nil
}

func (r *ExposureReconciler) publish(exposure *apiv1alpha1.Exposure, decision reconcile.ExposureDecision) {
	publishConditions(&exposure.Status.Conditions, decision.Conditions, exposure.Generation, r.Clock)
	exposure.Status.ObservedGeneration = exposure.Generation
	r.Metrics.Observe(exposureController, exposure.Status.Conditions)
	for _, e := range decision.Events {
		r.Recorder.Event(exposure, e.Type, e.Reason, e.Message)
	}
}

func (r *ExposureReconciler) finalize(ctx context.Context, exposure *apiv1alpha1.Exposure) (ctrl.Result, error) {
	if !controllerutil.ContainsFinalizer(exposure, apiv1alpha1.ExposureFinalizer) {
		return ctrl.Result{}, nil
	}
	in := reconcile.ExposureInput{}
	credentials, tunnel, err := r.resolveTunnel(ctx, exposure, &in)
	if err == nil && in.TunnelFound && in.AccountFound && in.AccountReady {
		if exposure.Status.AccessAppID != "" {
			if derr := r.Provider.DeleteAccessApplication(ctx, credentials, exposure.Status.AccessAppID); derr != nil {
				return ctrl.Result{}, derr
			}
		}
		if exposure.Status.Hostname != "" && tunnel != nil {
			if derr := r.Provider.DeleteDNSRecord(ctx, credentials, tunnel.Spec.Zone, exposure.Status.Hostname); derr != nil {
				return ctrl.Result{}, derr
			}
		}
	}
	if err != nil {
		return ctrl.Result{}, err
	}
	controllerutil.RemoveFinalizer(exposure, apiv1alpha1.ExposureFinalizer)
	return ctrl.Result{}, r.Update(ctx, exposure)
}

// SetupWithManager registers the Exposure controller with the manager. Service
// changes requeue Exposures in the same namespace (backend liveness).
func (r *ExposureReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&apiv1alpha1.Exposure{}).
		Watches(&apiv1alpha1.Tunnel{}, handler.EnqueueRequestsFromMapFunc(r.tunnelToExposures)).
		Named(exposureController).
		Complete(r)
}

// tunnelToExposures maps a Tunnel event to its Exposures' reconcile requests.
func (r *ExposureReconciler) tunnelToExposures(ctx context.Context, object client.Object) []ctrl.Request {
	tunnel, ok := object.(*apiv1alpha1.Tunnel)
	if !ok {
		return nil
	}
	var exposures apiv1alpha1.ExposureList
	if err := r.List(ctx, &exposures); err != nil {
		return nil
	}
	var requests []ctrl.Request
	for i := range exposures.Items {
		if exposures.Items[i].Spec.TunnelRef.Name == tunnel.Name && exposures.Items[i].Namespace == tunnel.Namespace {
			requests = append(requests, ctrl.Request{NamespacedName: types.NamespacedName{
				Namespace: exposures.Items[i].Namespace,
				Name:      exposures.Items[i].Name,
			}})
		}
	}
	return requests
}
