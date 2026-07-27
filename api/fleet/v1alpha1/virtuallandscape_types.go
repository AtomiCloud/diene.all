package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// VirtualLandscapeSpec is the desired state of a VirtualLandscape.
//
// A VirtualLandscape is the envelope/registrar entry: it is PR-gated reference
// data with NO reconciler. It is MULTI-TENANT — many platforms serve into one
// envelope and there is no owner field, because collisions are impossible by
// construction: every hostname derives from the declaring platform's own slot.
//
// Two refusals live outside CRD validation because both span objects and both
// are enforced by the owning controllers: deletion is refused while anything
// references the envelope, and REMOVING a host from spec.hosts is refused while
// that host still serves the envelope (release requires every serve fragment
// for the host-envelope pair to be gone; a serve flag flipped false is not
// sufficient).
type VirtualLandscapeSpec struct {
	// Hosts are the Landscape names that MAY serve this envelope.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinItems=1
	// +kubebuilder:validation:MaxItems=64
	// +listType=set
	// +kubebuilder:validation:items:MinLength=1
	// +kubebuilder:validation:items:MaxLength=63
	// +kubebuilder:validation:items:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
	Hosts []string `json:"hosts"`
}

// VirtualLandscapeStatus is the observed state of a VirtualLandscape.
//
// No controller in this operator writes it: VirtualLandscape is registry
// reference data. The subresource exists so a later admission/validation
// surface has a place to report without a schema break.
type VirtualLandscapeStatus struct {
	// Conditions follow the shared condition vocabulary.
	// +optional
	// +listType=map
	// +listMapKey=type
	Conditions []metav1.Condition `json:"conditions,omitempty"`

	// ObservedGeneration is the spec generation last observed.
	// +optional
	ObservedGeneration int64 `json:"observedGeneration,omitempty"`
}

// VirtualLandscape is the Schema for the virtuallandscapes API.
//
// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:scope=Cluster,shortName=vlsc
// +kubebuilder:printcolumn:name="Hosts",type=string,JSONPath=`.spec.hosts`
// +kubebuilder:printcolumn:name="Age",type=date,JSONPath=`.metadata.creationTimestamp`
type VirtualLandscape struct {
	metav1.TypeMeta   `json:",inline"` //nolint:revive // Kubernetes API roots require the ",inline" json tag; revive's struct-tag rule does not recognise it.
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   VirtualLandscapeSpec   `json:"spec,omitempty"`
	Status VirtualLandscapeStatus `json:"status,omitempty"`
}

// VirtualLandscapeList contains a list of VirtualLandscape.
//
// +kubebuilder:object:root=true
type VirtualLandscapeList struct {
	metav1.TypeMeta `json:",inline"` //nolint:revive // Kubernetes API roots require the ",inline" json tag; revive's struct-tag rule does not recognise it.
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []VirtualLandscape `json:"items"`
}

var _ = SchemeBuilder.Register(&VirtualLandscape{}, &VirtualLandscapeList{})
