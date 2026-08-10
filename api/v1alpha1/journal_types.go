package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// ─── DOMAIN WIRING (sample) ──────────────────────────────────────────────────
// Journal is the deliberately minimal second toy controller. It exists only to
// prove independent per-controller `--enable` registration and the shared
// condition vocabulary; it owns no external resource and keeps no ledger entry.

// JournalSpec is the desired state of a Journal.
type JournalSpec struct {
	// Message is the journal entry text.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=1024
	Message string `json:"message"`
}

// JournalStatus is the observed state of a Journal.
type JournalStatus struct {
	// Conditions follow the standard metav1.Condition vocabulary (Ready only).
	// +optional
	// +listType=map
	// +listMapKey=type
	Conditions []metav1.Condition `json:"conditions,omitempty"`

	// ObservedGeneration is the spec generation last reconciled.
	// +optional
	ObservedGeneration int64 `json:"observedGeneration,omitempty"`
}

// Journal is the Schema for the journals API.
//
// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:scope=Namespaced,shortName=jn
// +kubebuilder:printcolumn:name="Ready",type=string,JSONPath=`.status.conditions[?(@.type=="Ready")].status`
// +kubebuilder:printcolumn:name="Age",type=date,JSONPath=`.metadata.creationTimestamp`
type Journal struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   JournalSpec   `json:"spec,omitempty"`
	Status JournalStatus `json:"status,omitempty"`
}

// JournalList contains a list of Journal.
//
// +kubebuilder:object:root=true
type JournalList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []Journal `json:"items"`
}

var _ = SchemeBuilder.Register(&Journal{}, &JournalList{})

// ─── END DOMAIN WIRING (sample) ──────────────────────────────────────────────
