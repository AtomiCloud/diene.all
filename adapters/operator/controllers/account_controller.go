package controllers

import (
	"context"

	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"

	"github.com/AtomiCloud/diene.boron/adapters/operator/cloudflare"
	"github.com/AtomiCloud/diene.boron/adapters/operator/kube"
	"github.com/AtomiCloud/diene.boron/adapters/operator/metrics"
	apiv1alpha1 "github.com/AtomiCloud/diene.boron/api/v1alpha1"
	"github.com/AtomiCloud/diene.boron/lib/operator/reconcile"
)

const accountController = "account"

// AccountReconciler reconciles an Account: it validates the Cloudflare API
// token exactly once per Account (never per Tunnel/Exposure) and publishes
// TokenValid/Ready. It is thin: it maps API input, invokes the pure reconcile
// service, and flips Kubernetes status, events, and metrics.
type AccountReconciler struct {
	client.Client
	Clock    kube.Clock
	Recorder kube.Recorder
	Secrets  kube.SecretPort
	Provider cloudflare.Port
	Metrics  metrics.Recorder
}

// +kubebuilder:rbac:groups=boron.atomi.cloud,resources=accounts,verbs=get;list;watch;update
// +kubebuilder:rbac:groups=boron.atomi.cloud,resources=accounts/status,verbs=get;update;patch
// +kubebuilder:rbac:groups="",resources=secrets,verbs=get;list;watch
// +kubebuilder:rbac:groups="",resources=events,verbs=create;patch
// +kubebuilder:rbac:groups=authentication.k8s.io,resources=tokenreviews,verbs=create
// +kubebuilder:rbac:groups=authorization.k8s.io,resources=subjectaccessreviews,verbs=create
// +kubebuilder:rbac:groups=coordination.k8s.io,resources=leases,verbs=get;create;update

// Reconcile validates the Account's credentials and publishes its readiness.
func (r *AccountReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	r.Metrics.Tick(accountController)

	var account apiv1alpha1.Account
	if err := r.Get(ctx, req.NamespacedName, &account); err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}

	lookup, err := r.Secrets.ReadToken(ctx, account.Namespace, account.Spec.APITokenSecretRef.Name)
	if err != nil {
		return ctrl.Result{}, err
	}

	in := reconcile.AccountInput{SecretFound: lookup.SecretFound, TokenPresent: lookup.TokenPresent}
	if lookup.SecretFound && lookup.TokenPresent {
		in.Checked = true
		credentials := cloudflare.Credentials{AccountID: account.Spec.AccountID, APIToken: lookup.Token}
		switch verr := r.Provider.ValidateToken(ctx, credentials); {
		case verr == nil:
			in.ProviderReachable = true
			in.TokenValid = true
		case isInvalidToken(verr):
			in.ProviderReachable = true
		default:
			in.ProviderMessage = verr.Error()
		}
	}

	decision := reconcile.DecideAccount(in)
	publishConditions(&account.Status.Conditions, decision.Conditions, account.Generation, r.Clock)
	account.Status.ObservedGeneration = account.Generation
	r.Metrics.Observe(accountController, account.Status.Conditions)
	for _, e := range decision.Events {
		r.Recorder.Event(&account, e.Type, e.Reason, e.Message)
	}
	return ctrl.Result{}, r.Status().Update(ctx, &account)
}

// SetupWithManager registers the Account controller with the manager.
func (r *AccountReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&apiv1alpha1.Account{}).
		Named(accountController).
		Complete(r)
}
