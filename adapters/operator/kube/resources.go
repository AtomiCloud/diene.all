package kube

import (
	"context"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
)

const payloadKey = "payload"

// OwnedConfigMap is an owner-verified projection of a managed ConfigMap.
type OwnedConfigMap struct {
	Name    string
	Payload string
}

// ConfigMapPort is the narrow owned-resource port a controller uses to converge a
// controller's owned ConfigMap set. Ownership is decided by the controller
// OwnerReference UID, never by a mutable label, so a foreign or spoof-labelled
// object is never counted, overwritten, or deleted.
type ConfigMapPort interface {
	// ListOwned returns the ConfigMaps whose controller-owner UID matches owner and
	// the subset of desiredNames held by a non-owned (foreign) object.
	ListOwned(ctx context.Context, owner client.Object, desiredNames []string) (owned []OwnedConfigMap, foreign []string, err error)
	// Upsert creates or updates an owner-referenced ConfigMap to payload.
	Upsert(ctx context.Context, owner client.Object, name, payload string) error
	// Delete removes a ConfigMap only when its controller-owner UID matches owner.
	Delete(ctx context.Context, owner client.Object, name string) error
}

// ConfigMapAdapter implements ConfigMapPort over a controller-runtime client.
type ConfigMapAdapter struct {
	client client.Client
	scheme *runtime.Scheme
	label  string
}

// NewConfigMapAdapter constructs a ConfigMapPort. The label is applied for
// observability only; ownership decisions use the controller-owner UID.
func NewConfigMapAdapter(c client.Client, scheme *runtime.Scheme, label string) ConfigMapAdapter {
	return ConfigMapAdapter{client: c, scheme: scheme, label: label}
}

// ListOwned classifies the namespace's ConfigMaps by controller-owner UID.
func (a ConfigMapAdapter) ListOwned(ctx context.Context, owner client.Object, desiredNames []string) ([]OwnedConfigMap, []string, error) {
	var list corev1.ConfigMapList
	if err := a.client.List(ctx, &list, client.InNamespace(owner.GetNamespace())); err != nil {
		return nil, nil, err
	}
	desired := make(map[string]bool, len(desiredNames))
	for _, name := range desiredNames {
		desired[name] = true
	}

	var owned []OwnedConfigMap
	var foreign []string
	for i := range list.Items {
		cm := &list.Items[i]
		switch {
		case ownedBy(cm, owner):
			owned = append(owned, OwnedConfigMap{Name: cm.Name, Payload: cm.Data[payloadKey]})
		case desired[cm.Name]:
			foreign = append(foreign, cm.Name)
		default:
			// unrelated ConfigMap: neither owned nor a desired-name collision.
		}
	}
	return owned, foreign, nil
}

// Upsert creates the ConfigMap or updates its payload when owned. A pre-existing
// foreign object at the name is reported as an already-exists conflict.
func (a ConfigMapAdapter) Upsert(ctx context.Context, owner client.Object, name, payload string) error {
	var cm corev1.ConfigMap
	err := a.client.Get(ctx, client.ObjectKey{Namespace: owner.GetNamespace(), Name: name}, &cm)
	if apierrors.IsNotFound(err) {
		desired := &corev1.ConfigMap{
			ObjectMeta: metav1.ObjectMeta{
				Name:      name,
				Namespace: owner.GetNamespace(),
				Labels:    map[string]string{a.label: owner.GetName()},
			},
			Data: map[string]string{payloadKey: payload},
		}
		if refErr := controllerutil.SetControllerReference(owner, desired, a.scheme); refErr != nil {
			return refErr
		}
		return a.client.Create(ctx, desired)
	}
	if err != nil {
		return err
	}
	if !ownedBy(&cm, owner) {
		return apierrors.NewAlreadyExists(corev1.Resource("configmaps"), name)
	}
	if cm.Data[payloadKey] == payload {
		return nil
	}
	if cm.Data == nil {
		cm.Data = map[string]string{}
	}
	cm.Data[payloadKey] = payload
	return a.client.Update(ctx, &cm)
}

// Delete removes an owned ConfigMap. A foreign or absent object is left untouched.
func (a ConfigMapAdapter) Delete(ctx context.Context, owner client.Object, name string) error {
	var cm corev1.ConfigMap
	err := a.client.Get(ctx, client.ObjectKey{Namespace: owner.GetNamespace(), Name: name}, &cm)
	if apierrors.IsNotFound(err) {
		return nil
	}
	if err != nil {
		return err
	}
	if !ownedBy(&cm, owner) {
		return nil // never delete a foreign object
	}
	return client.IgnoreNotFound(a.client.Delete(ctx, &cm))
}

func ownedBy(object metav1.Object, owner client.Object) bool {
	ref := metav1.GetControllerOf(object)
	return ref != nil && ref.UID == owner.GetUID()
}
