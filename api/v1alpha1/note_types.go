package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// ─── DOMAIN WIRING (sample) ──────────────────────────────────────────────────
// The Note toy CRD mirrors the family Note sample domain. Everything between the
// fences is replaceable per instance; the reusable machinery never names these
// types except through the composition root.

// NoteFinalizer guards owned-resource cleanup and ledger orphaning on delete.
const NoteFinalizer = "sample.diene.atomi.cloud/note-finalizer"

// NoteSpec is the desired state of a Note.
type NoteSpec struct {
	// Title is the human-readable note title.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=253
	Title string `json:"title"`

	// Body is the note contents rendered into the owned ConfigMap set.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	Body string `json:"body"`

	// Category classifies the note.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:Enum=personal;work;archive
	Category string `json:"category"`

	// Replicas is the desired number of owned ConfigMap copies. It drives the
	// blast-brake demonstration when a reconcile would delete more than the
	// configured share of existing copies in a single tick.
	// +kubebuilder:validation:Minimum=0
	// +kubebuilder:validation:Maximum=50
	// +kubebuilder:default=1
	Replicas int32 `json:"replicas,omitempty"`
}

// NoteStatus is the observed state of a Note.
type NoteStatus struct {
	// Conditions follow the standard metav1.Condition vocabulary
	// (Ready / Drifted / Conflict / WaitingForEndpoint / BlastBrakeTripped).
	// +optional
	// +listType=map
	// +listMapKey=type
	Conditions []metav1.Condition `json:"conditions,omitempty"`

	// ObservedGeneration is the spec generation last reconciled.
	// +optional
	ObservedGeneration int64 `json:"observedGeneration,omitempty"`

	// OwnedConfigMaps counts the owned ConfigMap copies currently converged.
	// +optional
	OwnedConfigMaps int32 `json:"ownedConfigMaps,omitempty"`

	// LedgerRef is a pointer to the durable ledger entry for this Note. It is a
	// coordinate, never a secret value.
	// +optional
	LedgerRef string `json:"ledgerRef,omitempty"`
}

// Note is the Schema for the notes API.
//
// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:scope=Namespaced,shortName=nt
// +kubebuilder:printcolumn:name="Category",type=string,JSONPath=`.spec.category`
// +kubebuilder:printcolumn:name="Copies",type=integer,JSONPath=`.status.ownedConfigMaps`
// +kubebuilder:printcolumn:name="Ready",type=string,JSONPath=`.status.conditions[?(@.type=="Ready")].status`
// +kubebuilder:printcolumn:name="Age",type=date,JSONPath=`.metadata.creationTimestamp`
type Note struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   NoteSpec   `json:"spec,omitempty"`
	Status NoteStatus `json:"status,omitempty"`
}

// NoteList contains a list of Note.
//
// +kubebuilder:object:root=true
type NoteList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []Note `json:"items"`
}

var _ = SchemeBuilder.Register(&Note{}, &NoteList{})

// ─── END DOMAIN WIRING (sample) ──────────────────────────────────────────────
