package v1alpha1

import metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

// DecommissionTargetReference identifies the object whose owning controller
// must execute the ordered teardown ladder.
type DecommissionTargetReference struct {
	// Kind names the target kind. The owning-controller registry validates
	// whether that kind is dispatchable at reconcile time.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=63
	// +kubebuilder:validation:Pattern=`^[A-Z][A-Za-z0-9]*$`
	Kind string `json:"kind"`
	// Name is the target object name.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=253
	// +kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$`
	Name string `json:"name"`
}

// DecommissionSpec is explicit destructive intent. This lane supplies only
// the schema; controller dispatch and destructive behavior are deliberately
// absent.
//
// +kubebuilder:validation:XValidation:rule="self.confirm == self.targetRef.name",message="confirm must exactly match targetRef.name"
type DecommissionSpec struct {
	// TargetRef identifies the object being torn down.
	// +kubebuilder:validation:Required
	TargetRef DecommissionTargetReference `json:"targetRef"`
	// Confirm must re-type the exact target name as deletion friction.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=253
	Confirm string `json:"confirm"`
}

// DecommissionStatus exposes the strict condition ladder. The owning target
// controller advances RefsClear -> Snapshotted -> ExternalsDeleted ->
// LedgerPurged -> TargetDeleted before self-deleting this tombstone.
type DecommissionStatus struct {
	// Conditions are the ordered teardown proof ladder.
	// +optional
	// +listType=map
	// +listMapKey=type
	Conditions []metav1.Condition `json:"conditions,omitempty"`
	// ObservedGeneration is the spec generation last reconciled.
	// +optional
	ObservedGeneration int64 `json:"observedGeneration,omitempty"`
}

// Decommission is the Schema for the decommissions API.
//
// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:scope=Namespaced,shortName=decom
// +kubebuilder:printcolumn:name="Kind",type=string,JSONPath=`.spec.targetRef.kind`
// +kubebuilder:printcolumn:name="Target",type=string,JSONPath=`.spec.targetRef.name`
// +kubebuilder:printcolumn:name="Deleted",type=string,JSONPath=`.status.conditions[?(@.type=="TargetDeleted")].status`
// +kubebuilder:printcolumn:name="Age",type=date,JSONPath=`.metadata.creationTimestamp`
type Decommission struct {
	metav1.TypeMeta   `json:",inline"` //nolint:revive // Kubernetes API root inline tag.
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   DecommissionSpec   `json:"spec,omitempty"`
	Status DecommissionStatus `json:"status,omitempty"`
}

// DecommissionList contains a list of Decommission.
//
// +kubebuilder:object:root=true
type DecommissionList struct {
	metav1.TypeMeta `json:",inline"` //nolint:revive // Kubernetes API root inline tag.
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []Decommission `json:"items"`
}

var _ = SchemeBuilder.Register(&Decommission{}, &DecommissionList{})
