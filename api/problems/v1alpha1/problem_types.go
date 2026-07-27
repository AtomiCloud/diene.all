package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
)

// ProblemEndpoint records where a catalogued problem can occur. It is a
// documentation aid for the rendered portal page, never a routing input: the
// portal serves whatever path each entry's pre-minted type URI carries.
type ProblemEndpoint struct {
	// Method is the HTTP method, upper-case.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MaxLength=16
	// +kubebuilder:validation:Pattern=`^[A-Z]+$`
	Method string `json:"method"`

	// Path is the request path the problem can surface on. Path templates such
	// as /notes/{id} are ordinary values here.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=512
	// +kubebuilder:validation:Pattern=`^/`
	Path string `json:"path"`
}

// ProblemEntry is one catalogued problem inside a row. The entry's id is the
// within-row half of the merge component's (version, id) key, and map-list
// semantics on the containing field make a duplicate id an admission rejection
// rather than a merge-time surprise.
type ProblemEntry struct {
	// ID is the problem's snake_case identifier. Sub-scoping a service's
	// problems lives inside this id: module is not an identity field.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=63
	// +kubebuilder:validation:Pattern=`^[a-z][a-z0-9_]*$`
	ID string `json:"id"`

	// Type is the PRE-MINTED RFC 9457 problem type URI, emitted by the same
	// single-source builder a service puts in its wire responses. Only the URI
	// SHAPE is structural here; whether it matches the builder's template is the
	// merge component's semantic check, never a CRD rule.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MaxLength=2048
	// +kubebuilder:validation:Pattern=`^https://\S+$`
	Type string `json:"type"`

	// Title is the human-readable problem title rendered on the portal page.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=253
	Title string `json:"title"`

	// Status is the HTTP status this problem maps to — the exception-to-status
	// mapper's data.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:Minimum=100
	// +kubebuilder:validation:Maximum=599
	Status int32 `json:"status"`

	// Recoverable states whether a client can retry or recover, or whether the
	// problem is terminal.
	// +kubebuilder:validation:Required
	Recoverable bool `json:"recoverable"`

	// Schema is the JSON Schema of the problem's data extension, carried
	// verbatim. The preserve-unknown boundary is EXACTLY here: this object keeps
	// every key the emitter wrote, including vendor extensions the CRD has never
	// heard of, while every other unknown field in the CR is pruned normally.
	// Whether these bytes are well-formed JSON Schema is the merge component's
	// semantic check, not an admission rule.
	// +kubebuilder:validation:Required
	// +kubebuilder:pruning:PreserveUnknownFields
	// +kubebuilder:validation:Type=object
	Schema runtime.RawExtension `json:"schema"`

	// Endpoints lists where the problem can occur, as a documentation aid.
	// +optional
	// +listType=atomic
	// +kubebuilder:validation:MaxItems=64
	Endpoints []ProblemEndpoint `json:"endpoints,omitempty"`
}

// ProblemSpec is ONE catalog row: exactly one
// (platform, service, landscape, version) tuple and the whole set of problems
// that release catalogues. A service's release rewrites the ENTIRE row in one
// write, and a version bump is a NEW CR rather than an in-place spec.version
// mutation, so all four identity fields are immutable. module is deliberately
// absent from the identity: sub-scoping lives inside an entry's id.
type ProblemSpec struct {
	// Platform is the owning platform. By convention the CR also lives in the
	// namespace of the same name, but that convention is NOT enforced here: root
	// CEL cannot read metadata.namespace, so namespace == platform is deferred
	// to the admission-webhook obligation recorded in the docs.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=63
	// +kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
	// +kubebuilder:validation:XValidation:rule="self == oldSelf",message="platform is immutable"
	Platform string `json:"platform"`

	// Service is the cataloguing service.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=63
	// +kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
	// +kubebuilder:validation:XValidation:rule="self == oldSelf",message="service is immutable"
	Service string `json:"service"`

	// Landscape is the landscape row this catalog was materialized for. Rows for
	// the same (platform, service, version, id) are expected to be
	// byte-identical across landscapes; divergence is a merge conflict the merge
	// component reports, never an admission rejection.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=63
	// +kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
	// +kubebuilder:validation:XValidation:rule="self == oldSelf",message="landscape is immutable"
	Landscape string `json:"landscape"`

	// Version is the service's major API version snapshot this row catalogues.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MaxLength=16
	// +kubebuilder:validation:Pattern=`^v\d+$`
	// +kubebuilder:validation:XValidation:rule="self == oldSelf",message="version is immutable — a version bump is a new CR"
	Version string `json:"version"`

	// Problems is the whole catalog for this row, keyed by id. It is OPTIONAL
	// because a release that catalogues nothing must still be expressible as an
	// empty row — the emitter rewrites the entire row every release, so an
	// absent list is a meaningful state rather than a missing field. Map-list
	// semantics make a duplicate id within one row an admission rejection: the
	// within-row half of the merge key is structural, while cross-row conflicts
	// are not.
	// +optional
	// +listType=map
	// +listMapKey=id
	// +kubebuilder:validation:MaxItems=1024
	Problems []ProblemEntry `json:"problems,omitempty"`
}

// ProblemStatus is the observed publication state of the row. Nothing in THIS
// binary writes it in Phase 2: the merge component (erbium's error-portal job)
// patches it on delta using the vocabulary Published, SchemaInvalid and Stale.
// That vocabulary is deliberately NOT encoded as an enum — condition types on
// metav1.Condition stay open here exactly as they do on every sibling kind.
type ProblemStatus struct {
	// Conditions carry Published, SchemaInvalid and Stale, written by the merge
	// component.
	// +optional
	// +listType=map
	// +listMapKey=type
	Conditions []metav1.Condition `json:"conditions,omitempty"`
	// ObservedGeneration is the spec generation last processed by the merge
	// component.
	// +optional
	ObservedGeneration int64 `json:"observedGeneration,omitempty"`
}

// Problem is the Schema for the problems API.
//
// SCHEMA-ONLY in Phase 2. This lane ships the structural schema and its CEL
// rules and nothing else: there is no reconciler, no webhook server and no merge
// loop for Problem in this binary. The merge component writes every status
// condition (the erbium contract), folding in later behind the reserved seventh
// --enable-problem seam that already exists in internal/operatorruntime and is
// untouched here. The traffic controller separately publishes the derived edge
// catalog doc, and frontends classify errors from that doc — they never read
// this CR at runtime.
//
// Two conventions are recorded but NOT enforced structurally. First,
// namespace == platform: root CEL cannot read metadata.namespace, so it is
// deferred to the named admission-webhook obligation. Second, semantic validity
// — schema being well-formed JSON Schema, type matching the single-source
// builder template, cross-CR conflicts for one (platform, service, version, id),
// byte-identical landscape rows, and staleness or publication state — all
// require cross-object context admission does not have and belong to the merge
// component.
//
// The root rule below pins the row-name convention. As a documented side effect,
// a CR that omits spec entirely fails it at admission, which makes spec
// effectively required.
//
// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:scope=Namespaced,shortName=prb
// +kubebuilder:printcolumn:name="Service",type=string,JSONPath=`.spec.service`
// +kubebuilder:printcolumn:name="Landscape",type=string,JSONPath=`.spec.landscape`
// +kubebuilder:printcolumn:name="Version",type=string,JSONPath=`.spec.version`
// +kubebuilder:printcolumn:name="Published",type=string,JSONPath=`.status.conditions[?(@.type=="Published")].status`
// +kubebuilder:printcolumn:name="Age",type=date,JSONPath=`.metadata.creationTimestamp`
// +kubebuilder:validation:XValidation:rule="self.metadata.name == self.spec.service + '-' + self.spec.landscape + '-' + self.spec.version",message="name must be {service}-{landscape}-{version}"
type Problem struct {
	metav1.TypeMeta   `json:",inline"` //nolint:revive // Kubernetes API root inline tag.
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   ProblemSpec   `json:"spec,omitempty"`
	Status ProblemStatus `json:"status,omitempty"`
}

// ProblemList contains a list of Problem.
//
// +kubebuilder:object:root=true
type ProblemList struct {
	metav1.TypeMeta `json:",inline"` //nolint:revive // Kubernetes API root inline tag.
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []Problem `json:"items"`
}

var _ = SchemeBuilder.Register(&Problem{}, &ProblemList{})
