package v1alpha1

import (
	"bytes"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// jsonNull is the JSON literal an unset promotion step marshals to.
var jsonNull = []byte("null")

// PipelineStage is ONE step of a platform's promotion DAG, held verbatim.
//
// The step grammar is the platform home's own `stages:` grammar, rendered into
// this CR one-to-one by the compiler chart: a step is a bare landscape name, a
// parallel set of steps, or an object form carrying gate/soak/verification, and
// the object form is mixable inside a parallel set. That union of scalar, list
// and object is not expressible as a structural OpenAPI schema, so the step is
// carried unpruned and unvalidated at the CRD layer rather than re-typed into a
// normalized grammar this repository would have invented. Step-level validation
// belongs to the admission surface recorded as deferred, and to the platform
// controller's own compilation, which reports an unknown landscape as a
// condition rather than a schema rejection.
//
// +kubebuilder:validation:Type=""
// +kubebuilder:pruning:PreserveUnknownFields
type PipelineStage struct {
	// Raw is the step's JSON exactly as authored.
	Raw []byte `json:"-"`
}

// MarshalJSON writes the step back out verbatim.
func (s PipelineStage) MarshalJSON() ([]byte, error) {
	if len(s.Raw) > 0 {
		return s.Raw, nil
	}
	return jsonNull, nil
}

// UnmarshalJSON stores the step's JSON verbatim.
func (s *PipelineStage) UnmarshalJSON(data []byte) error {
	if len(data) > 0 && !bytes.Equal(data, jsonNull) {
		s.Raw = append(s.Raw[0:0], data...)
	}
	return nil
}

// PlatformInfisicalSpec is the platform's one Infisical project.
type PlatformInfisicalSpec struct {
	// ProjectSlug is the project slug; one platform is one Infisical project.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=63
	// +kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
	ProjectSlug string `json:"projectSlug"`

	// ServiceFolders selects the folder-prefixed key layout consumers depend on.
	// +kubebuilder:validation:Required
	ServiceFolders bool `json:"serviceFolders"`
}

// PlatformSoSSpec is the platform's registration into the operator-internal
// SoS project, which is where per-environment machine identities are recorded.
type PlatformSoSSpec struct {
	// Register requests SoS registration for this platform.
	// +kubebuilder:validation:Required
	Register bool `json:"register"`
}

// PlatformPipelineSpec is the platform's promotion DAG.
type PlatformPipelineSpec struct {
	// Stages is the ordered promotion DAG, rendered one-to-one from the platform
	// home's own manifest and never hand-authored on this CR.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinItems=1
	// +kubebuilder:validation:MaxItems=64
	Stages []PipelineStage `json:"stages"`
}

// PlatformSpec is the desired state of a Platform.
//
// A Platform is a singleton per platform, rendered by the fleet compiler chart.
// Its name must equal its namespace; that invariant spans metadata fields CRD
// validation cannot read, so it belongs to the deferred admission surface and
// is stated here rather than silently dropped.
type PlatformSpec struct {
	// Infisical is the platform's one project.
	// +kubebuilder:validation:Required
	Infisical PlatformInfisicalSpec `json:"infisical"`

	// SoS is the operator-internal registration half of the secret-homes split.
	// +kubebuilder:validation:Required
	SoS PlatformSoSSpec `json:"sos"`

	// Pipeline is the promotion DAG the per-service Kargo objects compile from.
	// +kubebuilder:validation:Required
	Pipeline PlatformPipelineSpec `json:"pipeline"`
}

// PlatformStatus is the observed state of a Platform.
type PlatformStatus struct {
	// Belt is DERIVED from the platform's row CRs and is never authored in spec.
	// The Infisical environments this controller creates mirror it exactly.
	// +optional
	// +listType=set
	Belt []string `json:"belt,omitempty"`

	// Conditions follow the shared condition vocabulary; the platform controller
	// additionally reports InfisicalProvisioned, SoSRegistered and
	// PipelineRendered here.
	// +optional
	// +listType=map
	// +listMapKey=type
	Conditions []metav1.Condition `json:"conditions,omitempty"`

	// ObservedGeneration is the spec generation last reconciled.
	// +optional
	ObservedGeneration int64 `json:"observedGeneration,omitempty"`
}

// Platform is the Schema for the platforms API.
//
// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:scope=Namespaced,shortName=plat
// +kubebuilder:printcolumn:name="Project",type=string,JSONPath=`.spec.infisical.projectSlug`
// +kubebuilder:printcolumn:name="Ready",type=string,JSONPath=`.status.conditions[?(@.type=="Ready")].status`
// +kubebuilder:printcolumn:name="Age",type=date,JSONPath=`.metadata.creationTimestamp`
type Platform struct {
	metav1.TypeMeta   `json:",inline"` //nolint:revive // Kubernetes API roots require the ",inline" json tag; revive's struct-tag rule does not recognise it.
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   PlatformSpec   `json:"spec,omitempty"`
	Status PlatformStatus `json:"status,omitempty"`
}

// PlatformList contains a list of Platform.
//
// +kubebuilder:object:root=true
type PlatformList struct {
	metav1.TypeMeta `json:",inline"` //nolint:revive // Kubernetes API roots require the ",inline" json tag; revive's struct-tag rule does not recognise it.
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []Platform `json:"items"`
}

var _ = SchemeBuilder.Register(&Platform{}, &PlatformList{})
