package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// LandscapePurposeInfrastructureOnly is the only declared landscape purpose. It
// marks a landscape that carries host substrate only: platform materialization
// and every replicated-delivery selector reject it, and it never materializes a
// platform row. An absent purpose is an ordinary serving landscape.
const LandscapePurposeInfrastructureOnly = "infrastructure-only"

// LandscapeSpec is the desired state of a Landscape.
//
// A Landscape is a foreign-key anchor for the whole fleet registry: it is
// PR-gated reference data with NO reconciler, and deletion is refused while
// anything still references it (a reference check the owning controllers make;
// CRD validation cannot span objects).
type LandscapeSpec struct {
	// Region is the vendor region every resource anchored to this landscape
	// provisions into. It is IMMUTABLE: a landscape's region is load-bearing for
	// dependency placement and for the Infisical environment that mirrors it, and
	// a moved region would silently re-home live externals.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=63
	// +kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
	// +kubebuilder:validation:XValidation:rule="self == oldSelf",message="region is immutable"
	Region string `json:"region"`

	// Tier is METADATA ONLY. It is never consulted for provider-account
	// selection, realization type, or delivery: those are explicit fields on the
	// declaring resource. The tier vocabulary is deliberately open.
	// +optional
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=63
	// +kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
	Tier string `json:"tier,omitempty"`

	// Purpose narrows what the landscape may carry. The only declared value is
	// infrastructure-only; absent means an ordinary serving landscape.
	// +optional
	// +kubebuilder:validation:Enum=infrastructure-only
	Purpose string `json:"purpose,omitempty"`
}

// LandscapeStatus is the observed state of a Landscape.
//
// No controller in this operator writes it: Landscape is registry reference
// data. The subresource exists so a later admission/validation surface has a
// place to report without a schema break.
type LandscapeStatus struct {
	// Conditions follow the shared condition vocabulary.
	// +optional
	// +listType=map
	// +listMapKey=type
	Conditions []metav1.Condition `json:"conditions,omitempty"`

	// ObservedGeneration is the spec generation last observed.
	// +optional
	ObservedGeneration int64 `json:"observedGeneration,omitempty"`
}

// Landscape is the Schema for the landscapes API.
//
// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:scope=Cluster,shortName=lsc
// +kubebuilder:printcolumn:name="Region",type=string,JSONPath=`.spec.region`
// +kubebuilder:printcolumn:name="Tier",type=string,JSONPath=`.spec.tier`
// +kubebuilder:printcolumn:name="Purpose",type=string,JSONPath=`.spec.purpose`
// +kubebuilder:printcolumn:name="Age",type=date,JSONPath=`.metadata.creationTimestamp`
type Landscape struct {
	metav1.TypeMeta   `json:",inline"` //nolint:revive // Kubernetes API roots require the ",inline" json tag; revive's struct-tag rule does not recognise it.
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   LandscapeSpec   `json:"spec,omitempty"`
	Status LandscapeStatus `json:"status,omitempty"`
}

// LandscapeList contains a list of Landscape.
//
// +kubebuilder:object:root=true
type LandscapeList struct {
	metav1.TypeMeta `json:",inline"` //nolint:revive // Kubernetes API roots require the ",inline" json tag; revive's struct-tag rule does not recognise it.
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []Landscape `json:"items"`
}

var _ = SchemeBuilder.Register(&Landscape{}, &LandscapeList{})
