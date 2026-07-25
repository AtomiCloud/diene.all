package v1alpha1

import metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

// ExposureFinalizer guards Exposure deletion (Access Application + DNS cleanup).
const ExposureFinalizer = "boron.atomi.cloud/exposure-finalizer"

// Coordinates is the unchanged four-slot LPSM coordinate; instance is a
// separate required projection field on ExposureSpec, never a fifth slot.
type Coordinates struct {
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=63
	Landscape string `json:"landscape"`
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=63
	Platform string `json:"platform"`
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=63
	Service string `json:"service"`
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=63
	Module string `json:"module"`
}

// BackendReference names a k8s Service (and port) in the Exposure's namespace.
type BackendReference struct {
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=253
	Name string `json:"name"`
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:Minimum=1
	// +kubebuilder:validation:Maximum=65535
	Port int32 `json:"port"`
}

// ExposureSpec maps one derived hostname + path to one backend Service, gated
// by an ordered list of pre-existing Access policies: 1 CR = 1 CF Access
// Application. The hostname is never declared, always derived as
// <module>.<service>.<platform>.<instance>.<landscape>.<zone>. A different
// policy set for a different path is a SECOND Exposure (the superseded
// rules[]/defaultPolicyRef shapes are dead).
type ExposureSpec struct {
	// +kubebuilder:validation:Required
	TunnelRef SecretNameReference `json:"tunnelRef"`
	// +kubebuilder:validation:Required
	Coordinates Coordinates `json:"coordinates"`
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=63
	Instance string `json:"instance"`
	// +kubebuilder:validation:Pattern=`^/.*`
	// +kubebuilder:validation:MaxLength=253
	// +kubebuilder:default="/*"
	Path string `json:"path,omitempty"`
	// +kubebuilder:validation:Required
	Backend BackendReference `json:"backend"`
	// Policies is an ORDERED array of EXISTING, reusable CF Access policy
	// NAMES. The operator resolves each name to its policy id at reconcile
	// (names are unique-enforced; a rename is a BREAKING change) and never
	// authors a policy. Any missing name refuses the whole Exposure.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinItems=1
	Policies []string `json:"policies"`
	// +kubebuilder:validation:Optional
	// +kubebuilder:default=false
	AllowSharedBackend bool `json:"allowSharedBackend,omitempty"`
}

// ProgrammedRule is the ingress rule this Exposure contributes to its Tunnel's
// remote configuration once programmed. Cleared while the Exposure is refused
// or conflicted so a broken Exposure never holds a route.
type ProgrammedRule struct {
	// +optional
	Hostname string `json:"hostname,omitempty"`
	// +optional
	Path string `json:"path,omitempty"`
	// +optional
	Backend string `json:"backend,omitempty"`
}

// ExposureStatus reports admission, ref resolution, programming, and conflict.
type ExposureStatus struct {
	// +optional
	// +listType=map
	// +listMapKey=type
	Conditions []metav1.Condition `json:"conditions,omitempty"`
	// +optional
	ObservedGeneration int64 `json:"observedGeneration,omitempty"`
	// +optional
	Hostname string `json:"hostname,omitempty"`
	// +optional
	AccessAppID string `json:"accessAppId,omitempty"`
	// +optional
	ProgrammedRule ProgrammedRule `json:"programmedRule,omitempty"`
}

// Exposure maps a derived hostname + path to one backend Service behind one CF
// Access Application.
//
// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:scope=Namespaced,shortName=be
// +kubebuilder:printcolumn:name="Hostname",type=string,JSONPath=`.status.hostname`
// +kubebuilder:printcolumn:name="Programmed",type=string,JSONPath=`.status.conditions[?(@.type=="Programmed")].status`
// +kubebuilder:printcolumn:name="Conflict",type=string,JSONPath=`.status.conditions[?(@.type=="Conflicted")].status`
// +kubebuilder:printcolumn:name="Age",type=date,JSONPath=`.metadata.creationTimestamp`
type Exposure struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`
	Spec              ExposureSpec   `json:"spec,omitempty"`
	Status            ExposureStatus `json:"status,omitempty"`
}

// ExposureList contains a list of Exposure.
//
// +kubebuilder:object:root=true
type ExposureList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []Exposure `json:"items"`
}

var _ = SchemeBuilder.Register(&Exposure{}, &ExposureList{})
