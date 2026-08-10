package kube

import (
	"context"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/util/intstr"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
)

// tokenKey is the well-known key carrying the Cloudflare API token inside the
// SecretStore-materialized Secret. The token is always SecretStore-sourced
// (cobalt ClusterSecretStore → carbon platform SecretStore); Boron only ever
// reads the resulting Secret — it never carries a token in a CR field.
const tokenKey = "token"

// TokenLookup is the Secret read result for an Account's apiTokenSecretRef.
type TokenLookup struct {
	SecretFound  bool
	TokenPresent bool
	Token        string
}

// SecretPort reads the Account's referenced api-token Secret.
type SecretPort interface {
	ReadToken(ctx context.Context, namespace, name string) (TokenLookup, error)
}

// SecretAdapter implements SecretPort over a controller-runtime client.
type SecretAdapter struct {
	client client.Client
}

// NewSecretAdapter constructs a SecretPort.
func NewSecretAdapter(c client.Client) SecretAdapter {
	return SecretAdapter{client: c}
}

// ReadToken loads the referenced Secret and projects its token key.
func (a SecretAdapter) ReadToken(ctx context.Context, namespace, name string) (TokenLookup, error) {
	var secret corev1.Secret
	err := a.client.Get(ctx, client.ObjectKey{Namespace: namespace, Name: name}, &secret)
	if apierrors.IsNotFound(err) {
		return TokenLookup{}, nil
	}
	if err != nil {
		return TokenLookup{}, err
	}
	token := string(secret.Data[tokenKey])
	return TokenLookup{SecretFound: true, TokenPresent: token != "", Token: token}, nil
}

// BackendLookup is the Service read result for an Exposure's backend.
type BackendLookup struct {
	Found     bool
	PortFound bool
	Public    bool
}

// ServicePort reads an Exposure's backend Service.
type ServicePort interface {
	ReadBackend(ctx context.Context, namespace, name string, port int32, publicAnnotation string) (BackendLookup, error)
}

// ServiceAdapter implements ServicePort over a controller-runtime client.
type ServiceAdapter struct {
	client client.Client
}

// NewServiceAdapter constructs a ServicePort.
func NewServiceAdapter(c client.Client) ServiceAdapter {
	return ServiceAdapter{client: c}
}

// ReadBackend loads the backend Service, checks the port, and reports whether
// the Service is marked publicly routed (the shared-backend guardrail input).
func (a ServiceAdapter) ReadBackend(ctx context.Context, namespace, name string, port int32, publicAnnotation string) (BackendLookup, error) {
	var service corev1.Service
	err := a.client.Get(ctx, client.ObjectKey{Namespace: namespace, Name: name}, &service)
	if apierrors.IsNotFound(err) {
		return BackendLookup{}, nil
	}
	if err != nil {
		return BackendLookup{}, err
	}
	lookup := BackendLookup{Found: true, Public: service.Annotations[publicAnnotation] == "true"}
	for _, p := range service.Spec.Ports {
		if p.Port == port {
			lookup.PortFound = true
			break
		}
	}
	return lookup, nil
}

// DeploymentSpec is the desired owned cloudflared Deployment for a Tunnel.
type DeploymentSpec struct {
	Name        string
	Image       string
	Replicas    int32
	TunnelToken string
}

// DeploymentPort converges a Tunnel's owned cloudflared Deployment.
type DeploymentPort interface {
	// EnsureDeployment creates or updates the owned Deployment and returns its
	// currently available replica count.
	EnsureDeployment(ctx context.Context, owner client.Object, spec DeploymentSpec) (availableReplicas int32, err error)
	// DeleteDeployment removes the owned Deployment on Tunnel finalization.
	DeleteDeployment(ctx context.Context, owner client.Object, name string) error
}

// DeploymentAdapter implements DeploymentPort over a controller-runtime client.
type DeploymentAdapter struct {
	client client.Client
	scheme *runtime.Scheme
	label  string
}

// NewDeploymentAdapter constructs a DeploymentPort. The label is applied for
// observability only; ownership decisions use the controller-owner UID.
func NewDeploymentAdapter(c client.Client, scheme *runtime.Scheme, label string) DeploymentAdapter {
	return DeploymentAdapter{client: c, scheme: scheme, label: label}
}

// EnsureDeployment converges the owned cloudflared Deployment to spec. The
// tunnel token reaches cloudflared as an env var referencing the remote-managed
// run mode; ingress rules arrive via the API-pushed remote config (hot-reload),
// never a ConfigMap.
func (a DeploymentAdapter) EnsureDeployment(ctx context.Context, owner client.Object, spec DeploymentSpec) (int32, error) {
	var existing appsv1.Deployment
	err := a.client.Get(ctx, client.ObjectKey{Namespace: owner.GetNamespace(), Name: spec.Name}, &existing)
	if apierrors.IsNotFound(err) {
		desired := a.desired(owner, spec)
		if refErr := controllerutil.SetControllerReference(owner, desired, a.scheme); refErr != nil {
			return 0, refErr
		}
		if createErr := a.client.Create(ctx, desired); createErr != nil {
			return 0, createErr
		}
		return 0, nil
	}
	if err != nil {
		return 0, err
	}
	if !ownedBy(&existing, owner) {
		return 0, apierrors.NewAlreadyExists(appsv1.Resource("deployments"), spec.Name)
	}
	desired := a.desired(owner, spec)
	existing.Spec.Replicas = desired.Spec.Replicas
	existing.Spec.Template.Spec.Containers = desired.Spec.Template.Spec.Containers
	if updateErr := a.client.Update(ctx, &existing); updateErr != nil {
		return 0, updateErr
	}
	return existing.Status.AvailableReplicas, nil
}

// DeleteDeployment removes an owned Deployment. Foreign or absent objects are
// left untouched.
func (a DeploymentAdapter) DeleteDeployment(ctx context.Context, owner client.Object, name string) error {
	var existing appsv1.Deployment
	err := a.client.Get(ctx, client.ObjectKey{Namespace: owner.GetNamespace(), Name: name}, &existing)
	if apierrors.IsNotFound(err) {
		return nil
	}
	if err != nil {
		return err
	}
	if !ownedBy(&existing, owner) {
		return nil // never delete a foreign object
	}
	return client.IgnoreNotFound(a.client.Delete(ctx, &existing))
}

func (a DeploymentAdapter) desired(owner client.Object, spec DeploymentSpec) *appsv1.Deployment {
	replicas := spec.Replicas
	labels := map[string]string{a.label: owner.GetName()}
	return &appsv1.Deployment{
		ObjectMeta: metav1.ObjectMeta{
			Name:      spec.Name,
			Namespace: owner.GetNamespace(),
			Labels:    labels,
		},
		Spec: appsv1.DeploymentSpec{
			Replicas: &replicas,
			Selector: &metav1.LabelSelector{MatchLabels: labels},
			Template: corev1.PodTemplateSpec{
				ObjectMeta: metav1.ObjectMeta{Labels: labels},
				Spec: corev1.PodSpec{
					Containers: []corev1.Container{{
						Name:  "cloudflared",
						Image: spec.Image,
						Args:  []string{"tunnel", "--no-autoupdate", "run"},
						Env:   []corev1.EnvVar{{Name: "TUNNEL_TOKEN", Value: spec.TunnelToken}},
						ReadinessProbe: &corev1.Probe{
							ProbeHandler: corev1.ProbeHandler{
								HTTPGet: &corev1.HTTPGetAction{Path: "/ready", Port: intstr.FromInt32(2000)},
							},
						},
					}},
				},
			},
		},
	}
}

func ownedBy(object metav1.Object, owner client.Object) bool {
	ref := metav1.GetControllerOf(object)
	return ref != nil && ref.UID == owner.GetUID()
}
