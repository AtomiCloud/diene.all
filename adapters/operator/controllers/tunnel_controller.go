package controllers

import (
	"context"
	"slices"
	"strings"

	appsv1 "k8s.io/api/apps/v1"
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

// TunnelOwnerLabel decorates the owned cloudflared Deployment for observability.
// Ownership decisions use the controller OwnerReference UID, never this label.
const TunnelOwnerLabel = "boron.atomi.cloud/tunnel"

const tunnelController = "tunnel"

// TunnelReconciler reconciles a Tunnel: 1 CR = 1 Cloudflare Tunnel = 1 zone. It
// materializes the cloudflared Deployment at the fixed replica count, ensures
// the remote tunnel, pushes the API-managed (hot-reload) ingress configuration,
// and rolls up Account readiness + config-push result + replica health.
type TunnelReconciler struct {
	client.Client
	Clock       kube.Clock
	Recorder    kube.Recorder
	Secrets     kube.SecretPort
	Deployments kube.DeploymentPort
	Provider    cloudflare.Port
	Metrics     metrics.Recorder

	// CloudflaredImage is the pinned cloudflared image reference.
	CloudflaredImage string
}

// +kubebuilder:rbac:groups=boron.atomi.cloud,resources=tunnels,verbs=get;list;watch;update
// +kubebuilder:rbac:groups=boron.atomi.cloud,resources=tunnels/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=boron.atomi.cloud,resources=tunnels/finalizers,verbs=update
// +kubebuilder:rbac:groups=boron.atomi.cloud,resources=accounts,verbs=get;list;watch
// +kubebuilder:rbac:groups=boron.atomi.cloud,resources=exposures,verbs=get;list;watch
// +kubebuilder:rbac:groups=apps,resources=deployments,verbs=get;list;watch;create;update;patch;delete

// Reconcile drives a Tunnel toward its desired state.
func (r *TunnelReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	r.Metrics.Tick(tunnelController)

	var tunnel apiv1alpha1.Tunnel
	if err := r.Get(ctx, req.NamespacedName, &tunnel); err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}

	if !tunnel.DeletionTimestamp.IsZero() {
		return r.finalize(ctx, &tunnel)
	}
	if controllerutil.AddFinalizer(&tunnel, apiv1alpha1.TunnelFinalizer) {
		return ctrl.Result{}, r.Update(ctx, &tunnel)
	}
	return r.converge(ctx, &tunnel)
}

func (r *TunnelReconciler) converge(ctx context.Context, tunnel *apiv1alpha1.Tunnel) (ctrl.Result, error) {
	in := reconcile.TunnelInput{}

	credentials, accountState, err := r.resolveAccount(ctx, tunnel)
	if err != nil {
		return ctrl.Result{}, err
	}
	in.AccountFound = accountState.found
	in.AccountReady = accountState.ready

	if in.AccountFound && in.AccountReady {
		remote, terr := r.Provider.EnsureTunnel(ctx, credentials, tunnel.Name, tunnel.Spec.Zone)
		if terr != nil {
			in.ProviderMessage = terr.Error()
		} else {
			in.TunnelEnsured = true
			tunnel.Status.TunnelID = remote.ID

			available, derr := r.Deployments.EnsureDeployment(ctx, tunnel, kube.DeploymentSpec{
				Name:        "cloudflared-" + tunnel.Name,
				Image:       r.CloudflaredImage,
				Replicas:    reconcile.TunnelReplicas,
				TunnelToken: remote.Token,
			})
			if derr != nil {
				return ctrl.Result{}, derr
			}
			in.AvailableReplicas = available

			rules, rerr := r.collectRules(ctx, tunnel)
			if rerr != nil {
				return ctrl.Result{}, rerr
			}
			if perr := r.Provider.PushTunnelConfig(ctx, credentials, remote.ID, rules); perr != nil {
				in.ProviderMessage = perr.Error()
			} else {
				in.ConfigPushed = true
			}
		}
	}

	decision := reconcile.DecideTunnel(in)
	publishConditions(&tunnel.Status.Conditions, decision.Conditions, tunnel.Generation, r.Clock)
	tunnel.Status.ObservedGeneration = tunnel.Generation
	tunnel.Status.AvailableReplicas = in.AvailableReplicas
	r.Metrics.Observe(tunnelController, tunnel.Status.Conditions)
	for _, e := range decision.Events {
		r.Recorder.Event(tunnel, e.Type, e.Reason, e.Message)
	}
	return ctrl.Result{}, r.Status().Update(ctx, tunnel)
}

type accountState struct {
	found bool
	ready bool
}

// resolveAccount loads the Tunnel's Account (same namespace) and its credentials.
func (r *TunnelReconciler) resolveAccount(ctx context.Context, tunnel *apiv1alpha1.Tunnel) (cloudflare.Credentials, accountState, error) {
	var account apiv1alpha1.Account
	err := r.Get(ctx, client.ObjectKey{Namespace: tunnel.Namespace, Name: tunnel.Spec.AccountRef.Name}, &account)
	if apierrors.IsNotFound(err) {
		return cloudflare.Credentials{}, accountState{}, nil
	}
	if err != nil {
		return cloudflare.Credentials{}, accountState{}, err
	}
	state := accountState{found: true, ready: conditionTrue(account.Status.Conditions, reconcile.TypeReady)}
	if !state.ready {
		return cloudflare.Credentials{}, state, nil
	}
	lookup, err := r.Secrets.ReadToken(ctx, account.Namespace, account.Spec.APITokenSecretRef.Name)
	if err != nil {
		return cloudflare.Credentials{}, state, err
	}
	if !lookup.SecretFound || !lookup.TokenPresent {
		return cloudflare.Credentials{}, accountState{found: true}, nil
	}
	return cloudflare.Credentials{AccountID: account.Spec.AccountID, APIToken: lookup.Token}, state, nil
}

// collectRules assembles the tunnel's remote ingress configuration: one rule per
// programmed Exposure referencing this Tunnel, deterministically ordered.
func (r *TunnelReconciler) collectRules(ctx context.Context, tunnel *apiv1alpha1.Tunnel) ([]cloudflare.IngressRule, error) {
	var exposures apiv1alpha1.ExposureList
	if err := r.List(ctx, &exposures); err != nil {
		return nil, err
	}
	var rules []cloudflare.IngressRule
	for i := range exposures.Items {
		e := &exposures.Items[i]
		if e.Spec.TunnelRef.Name != tunnel.Name {
			continue
		}
		if e.Status.ProgrammedRule.Hostname == "" {
			continue
		}
		rules = append(rules, cloudflare.IngressRule{
			Hostname: e.Status.ProgrammedRule.Hostname,
			Path:     e.Status.ProgrammedRule.Path,
			Backend:  e.Status.ProgrammedRule.Backend,
		})
	}
	slices.SortFunc(rules, func(a, b cloudflare.IngressRule) int {
		return strings.Compare(a.Hostname+a.Path, b.Hostname+b.Path)
	})
	return rules, nil
}

func (r *TunnelReconciler) finalize(ctx context.Context, tunnel *apiv1alpha1.Tunnel) (ctrl.Result, error) {
	if !controllerutil.ContainsFinalizer(tunnel, apiv1alpha1.TunnelFinalizer) {
		return ctrl.Result{}, nil
	}
	// Delete the owned in-cluster Deployment; never destroy the external tunnel
	// record (finalizers clean owned cluster state, external records are orphaned).
	if err := r.Deployments.DeleteDeployment(ctx, tunnel, "cloudflared-"+tunnel.Name); err != nil {
		return ctrl.Result{}, err
	}
	controllerutil.RemoveFinalizer(tunnel, apiv1alpha1.TunnelFinalizer)
	return ctrl.Result{}, r.Update(ctx, tunnel)
}

// SetupWithManager registers the Tunnel controller with the manager. Exposure
// changes requeue their Tunnel so the remote config re-syncs.
func (r *TunnelReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&apiv1alpha1.Tunnel{}).
		Owns(&appsv1.Deployment{}).
		Watches(&apiv1alpha1.Exposure{}, handler.EnqueueRequestsFromMapFunc(r.exposureToTunnel)).
		Named(tunnelController).
		Complete(r)
}

// exposureToTunnel maps an Exposure event to its Tunnel's reconcile request.
func (r *TunnelReconciler) exposureToTunnel(ctx context.Context, object client.Object) []ctrl.Request {
	exposure, ok := object.(*apiv1alpha1.Exposure)
	if !ok || exposure.Spec.TunnelRef.Name == "" {
		return nil
	}
	var tunnels apiv1alpha1.TunnelList
	if err := r.List(ctx, &tunnels); err != nil {
		return nil
	}
	var requests []ctrl.Request
	for i := range tunnels.Items {
		if tunnels.Items[i].Name == exposure.Spec.TunnelRef.Name {
			requests = append(requests, ctrl.Request{NamespacedName: types.NamespacedName{
				Namespace: tunnels.Items[i].Namespace,
				Name:      tunnels.Items[i].Name,
			}})
		}
	}
	return requests
}
