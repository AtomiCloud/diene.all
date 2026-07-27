package v1alpha1

import metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

// VirtualLandscapeServiceSpec is one additive serve fragment. The hostname is
// derived from module, service, platform, and vlandscape and has no spec field.
type VirtualLandscapeServiceSpec struct {
	// Platform supplies the hostname's platform slot explicitly.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=63
	// +kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
	Platform string `json:"platform"`

	// VLandscape is the virtual-landscape envelope being served.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=63
	// +kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
	VLandscape string `json:"vlandscape"`

	// Service is the serving service.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=63
	// +kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
	Service string `json:"service"`

	// Module is the serving module.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=63
	// +kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
	Module string `json:"module"`

	// Landscape is the registered host row contributing this fragment.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=63
	// +kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
	Landscape string `json:"landscape"`

	// Serve is explicit intent to publish this row into the envelope record.
	// +kubebuilder:validation:Required
	Serve bool `json:"serve"`
}

// VirtualLandscapeServiceModuleStatus isolates the conditions of the one
// declared module while retaining the map shape shared controller machinery
// requires.
type VirtualLandscapeServiceModuleStatus struct {
	// Host is the derived hostname and is never authored in spec.
	// +optional
	Host string `json:"host,omitempty"`
	// Conditions use Accepted, NotInEnvelope, RecordPublished,
	// NoActiveServers, and Ready.
	// +optional
	// +listType=map
	// +listMapKey=type
	Conditions []metav1.Condition `json:"conditions,omitempty"`
}

// VirtualLandscapeServiceStatus is the observed serve-fragment state.
type VirtualLandscapeServiceStatus struct {
	// Host is the derived canonical hostname.
	// +optional
	Host string `json:"host,omitempty"`
	// Modules is map-keyed to preserve per-module condition isolation.
	// +optional
	Modules map[string]VirtualLandscapeServiceModuleStatus `json:"modules,omitempty"`
	// Conditions summarize Accepted, NotInEnvelope, RecordPublished,
	// NoActiveServers, and Ready for the fragment.
	// +optional
	// +listType=map
	// +listMapKey=type
	Conditions []metav1.Condition `json:"conditions,omitempty"`
	// ObservedGeneration is the spec generation last reconciled.
	// +optional
	ObservedGeneration int64 `json:"observedGeneration,omitempty"`
}

// VirtualLandscapeService is the Schema for the virtuallandscapeservices API.
//
// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:scope=Namespaced,shortName=vls
// +kubebuilder:printcolumn:name="VLandscape",type=string,JSONPath=`.spec.vlandscape`
// +kubebuilder:printcolumn:name="Landscape",type=string,JSONPath=`.spec.landscape`
// +kubebuilder:printcolumn:name="Serve",type=boolean,JSONPath=`.spec.serve`
// +kubebuilder:printcolumn:name="Ready",type=string,JSONPath=`.status.conditions[?(@.type=="Ready")].status`
// +kubebuilder:printcolumn:name="Age",type=date,JSONPath=`.metadata.creationTimestamp`
type VirtualLandscapeService struct {
	metav1.TypeMeta   `json:",inline"` //nolint:revive // Kubernetes API root inline tag.
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   VirtualLandscapeServiceSpec   `json:"spec,omitempty"`
	Status VirtualLandscapeServiceStatus `json:"status,omitempty"`
}

// VirtualLandscapeServiceList contains a list of VirtualLandscapeService.
//
// +kubebuilder:object:root=true
type VirtualLandscapeServiceList struct {
	metav1.TypeMeta `json:",inline"` //nolint:revive // Kubernetes API root inline tag.
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []VirtualLandscapeService `json:"items"`
}

var _ = SchemeBuilder.Register(&VirtualLandscapeService{}, &VirtualLandscapeServiceList{})
