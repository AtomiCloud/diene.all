package v1alpha1

import metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

// WebhookRouteTarget is a coordinate whose delivery address is derived per
// landing landscape. No raw URL or landscape stamp is stored here.
type WebhookRouteTarget struct {
	// Service is the receiver service.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=63
	// +kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
	Service string `json:"service"`
	// Module is the receiver module.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=63
	// +kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
	Module string `json:"module"`
}

// WebhookRouteSpec is one additive registered-endpoint fragment. Unknown
// providers without a scheme are reconcile-time UnknownProvider conditions:
// the shipped adapter registry is not an admission-time schema fact.
type WebhookRouteSpec struct {
	// Engine names the WebhookEngine internal tenant.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=63
	// +kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
	Engine string `json:"engine"`
	// Path is both the provider-facing URL path and the merge key.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=1024
	// +kubebuilder:validation:Pattern=`^/`
	Path string `json:"path"`
	// Provider names a shipped adapter or an adapterless provider class.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=63
	// +kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
	Provider string `json:"provider"`
	// Scheme declares adapterless verification. It is optional because shipped
	// adapters already own their scheme.
	// +kubebuilder:validation:Optional
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=63
	Scheme string `json:"scheme,omitempty"`
	// Target is the receiver coordinate; its address remains derived.
	// +kubebuilder:validation:Required
	Target WebhookRouteTarget `json:"target"`
}

// WebhookRouteStatus is the observed route-fragment state.
type WebhookRouteStatus struct {
	// Conditions use Accepted, UnknownProvider, Conflict, TargetNotServed and
	// Ready.
	// +optional
	// +listType=map
	// +listMapKey=type
	Conditions []metav1.Condition `json:"conditions,omitempty"`
	// ObservedGeneration is the spec generation last reconciled.
	// +optional
	ObservedGeneration int64 `json:"observedGeneration,omitempty"`
}

// WebhookRoute is the Schema for the webhookroutes API.
//
// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:scope=Namespaced,shortName=whr
// +kubebuilder:printcolumn:name="Engine",type=string,JSONPath=`.spec.engine`
// +kubebuilder:printcolumn:name="Provider",type=string,JSONPath=`.spec.provider`
// +kubebuilder:printcolumn:name="Path",type=string,JSONPath=`.spec.path`
// +kubebuilder:printcolumn:name="Ready",type=string,JSONPath=`.status.conditions[?(@.type=="Ready")].status`
// +kubebuilder:printcolumn:name="Age",type=date,JSONPath=`.metadata.creationTimestamp`
type WebhookRoute struct {
	metav1.TypeMeta   `json:",inline"` //nolint:revive // Kubernetes API root inline tag.
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   WebhookRouteSpec   `json:"spec,omitempty"`
	Status WebhookRouteStatus `json:"status,omitempty"`
}

// WebhookRouteList contains a list of WebhookRoute.
//
// +kubebuilder:object:root=true
type WebhookRouteList struct {
	metav1.TypeMeta `json:",inline"` //nolint:revive // Kubernetes API root inline tag.
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []WebhookRoute `json:"items"`
}

var _ = SchemeBuilder.Register(&WebhookRoute{}, &WebhookRouteList{})
