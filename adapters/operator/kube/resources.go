package kube

import (
	"context"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
)

// ConfigMapPort is the narrow owned-resource port a controller uses to converge
// a set of owner-labelled ConfigMaps. Keeping k8s resource operations behind this
// port keeps the controller thin and the lib free of k8s types.
type ConfigMapPort interface {
	// List returns the names of the ConfigMaps owned by ownerName in namespace.
	List(ctx context.Context, namespace, ownerName string) ([]string, error)
	// Ensure creates an owner-referenced ConfigMap copy carrying payload.
	Ensure(ctx context.Context, owner client.Object, name, payload string) error
	// Delete removes an owned ConfigMap copy; a missing copy is not an error.
	Delete(ctx context.Context, namespace, name string) error
}

// ConfigMapAdapter implements ConfigMapPort over a controller-runtime client.
type ConfigMapAdapter struct {
	client client.Client
	scheme *runtime.Scheme
	label  string
}

// NewConfigMapAdapter constructs a ConfigMapPort that labels and owner-references
// the ConfigMaps it manages with label.
func NewConfigMapAdapter(c client.Client, scheme *runtime.Scheme, label string) ConfigMapAdapter {
	return ConfigMapAdapter{client: c, scheme: scheme, label: label}
}

// List returns the owned ConfigMap names for ownerName.
func (a ConfigMapAdapter) List(ctx context.Context, namespace, ownerName string) ([]string, error) {
	var list corev1.ConfigMapList
	if err := a.client.List(ctx, &list, client.InNamespace(namespace), client.MatchingLabels{a.label: ownerName}); err != nil {
		return nil, err
	}
	names := make([]string, 0, len(list.Items))
	for i := range list.Items {
		names = append(names, list.Items[i].Name)
	}
	return names, nil
}

// Ensure creates an owner-referenced ConfigMap copy.
func (a ConfigMapAdapter) Ensure(ctx context.Context, owner client.Object, name, payload string) error {
	cm := &corev1.ConfigMap{
		ObjectMeta: metav1.ObjectMeta{
			Name:      name,
			Namespace: owner.GetNamespace(),
			Labels:    map[string]string{a.label: owner.GetName()},
		},
		Data: map[string]string{"payload": payload},
	}
	if err := controllerutil.SetControllerReference(owner, cm, a.scheme); err != nil {
		return err
	}
	return a.client.Create(ctx, cm)
}

// Delete removes an owned ConfigMap copy, ignoring an already-absent copy.
func (a ConfigMapAdapter) Delete(ctx context.Context, namespace, name string) error {
	cm := &corev1.ConfigMap{ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: namespace}}
	return client.IgnoreNotFound(a.client.Delete(ctx, cm))
}
