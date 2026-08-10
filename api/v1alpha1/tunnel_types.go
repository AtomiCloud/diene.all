package v1alpha1

import metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

// TunnelFinalizer guards Tunnel deletion (owned Deployment cleanup).
const TunnelFinalizer = "boron.atomi.cloud/tunnel-finalizer"

// TunnelSpec declares one Cloudflare Tunnel bound to one zone: 1 CR = 1 CF
// Tunnel = 1 zone. Needing another zone means creating another Tunnel — there
// is no multi-zone listener fan-out (the superseded listeners[] shape is dead).
// Replicas are fixed at 2 and deliberately not part of the spec (no HPA).
type TunnelSpec struct {
	// +kubebuilder:validation:Required
	AccountRef SecretNameReference `json:"accountRef"`
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=253
	// +kubebuilder:validation:Pattern=`^([a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$`
	Zone string `json:"zone"`
}

// TunnelStatus rolls up Account readiness, the remote (API-pushed, hot-reload)
// config-push result, and cloudflared replica health.
type TunnelStatus struct {
	// +optional
	// +listType=map
	// +listMapKey=type
	Conditions []metav1.Condition `json:"conditions,omitempty"`
	// +optional
	ObservedGeneration int64 `json:"observedGeneration,omitempty"`
	// +optional
	TunnelID string `json:"tunnelId,omitempty"`
	// +optional
	AvailableReplicas int32 `json:"availableReplicas,omitempty"`
}

// Tunnel is one Cloudflare Tunnel serving one zone; one Tunnel fans out to
// many Exposures.
//
// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:scope=Namespaced,shortName=bt
// +kubebuilder:printcolumn:name="Zone",type=string,JSONPath=`.spec.zone`
// +kubebuilder:printcolumn:name="Config",type=string,JSONPath=`.status.conditions[?(@.type=="ConfigSynced")].status`
// +kubebuilder:printcolumn:name="Replicas",type=integer,JSONPath=`.status.availableReplicas`
// +kubebuilder:printcolumn:name="Age",type=date,JSONPath=`.metadata.creationTimestamp`
type Tunnel struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`
	Spec              TunnelSpec   `json:"spec,omitempty"`
	Status            TunnelStatus `json:"status,omitempty"`
}

// TunnelList contains a list of Tunnel.
//
// +kubebuilder:object:root=true
type TunnelList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []Tunnel `json:"items"`
}

var _ = SchemeBuilder.Register(&Tunnel{}, &TunnelList{})
