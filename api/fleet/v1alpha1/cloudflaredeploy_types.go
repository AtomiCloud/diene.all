package v1alpha1

import metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

// CloudflareDesiredVersionFrom selects an uploaded Worker version by tag.
type CloudflareDesiredVersionFrom struct {
	// Tag is the Kargo-driven version tag.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=128
	Tag string `json:"tag"`
}

// CloudflareRolloutStep is one Cloudflare-native gradual deployment step.
type CloudflareRolloutStep struct {
	// Percent is the target version's Cloudflare traffic percentage.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:Minimum=1
	// +kubebuilder:validation:Maximum=100
	Percent int32 `json:"percent"`
	// Soak is the optional health-stable wait before advancing.
	// +kubebuilder:validation:Optional
	// +kubebuilder:validation:Pattern=`^[0-9]+(ns|us|ms|s|m|h)$`
	Soak string `json:"soak,omitempty"`
}

// CloudflareRollout is the opt-in gradual deployment policy.
type CloudflareRollout struct {
	// Strategy is Cloudflare-native gradual rollout.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:Enum=gradual
	Strategy string `json:"strategy"`
	// Steps ends at a full 100 percent deployment.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinItems=1
	// +kubebuilder:validation:MaxItems=32
	// +kubebuilder:validation:XValidation:rule="self.exists(step, step.percent == 100)",message="rollout steps must contain a 100 percent step"
	Steps []CloudflareRolloutStep `json:"steps"`
}

// CloudflareDeploySpec is per-version deployment intent. CI only uploads
// versions; this object is the sole deployment/pinning control.
//
// +kubebuilder:validation:XValidation:rule="has(self.desiredVersion) != has(self.desiredVersionFrom)",message="exactly one of desiredVersion or desiredVersionFrom is required"
type CloudflareDeploySpec struct {
	// ScriptName is the existing Worker script whose uploaded versions are
	// pinned and rolled out.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=128
	// +kubebuilder:validation:Pattern=`^[A-Za-z0-9_-]+$`
	ScriptName string `json:"scriptName"`
	// DesiredVersion selects an explicit uploaded version id.
	// +kubebuilder:validation:Optional
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=256
	DesiredVersion string `json:"desiredVersion,omitempty"`
	// DesiredVersionFrom selects an uploaded version through a Kargo-driven tag.
	// +kubebuilder:validation:Optional
	DesiredVersionFrom *CloudflareDesiredVersionFrom `json:"desiredVersionFrom,omitempty"`
	// Rollout is absent for a simple 100 percent deploy and present only when
	// gradual rollout is explicitly requested.
	// +kubebuilder:validation:Optional
	Rollout *CloudflareRollout `json:"rollout,omitempty"`
	// Pin repairs out-of-band deployment drift when true.
	// +kubebuilder:validation:Required
	Pin bool `json:"pin"`
}

// CloudflareAvailableVersion is one uploaded version in the status catalog.
type CloudflareAvailableVersion struct {
	// ID is the Cloudflare version id.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	ID string `json:"id"`
	// Tags are provider/Kargo labels associated with the version.
	// +optional
	// +listType=set
	Tags []string `json:"tags,omitempty"`
	// CreatedAt is the provider creation time.
	// +optional
	CreatedAt *metav1.Time `json:"createdAt,omitempty"`
}

// CloudflareDeploymentStatus is the active rollout position.
type CloudflareDeploymentStatus struct {
	// Step is the zero-based active rollout step.
	// +optional
	Step int32 `json:"step,omitempty"`
	// Percent is the target version's current traffic percentage.
	// +optional
	Percent int32 `json:"percent,omitempty"`
}

// CloudflareDeployStatus is the observed version and rollout state.
type CloudflareDeployStatus struct {
	// AvailableVersions is the uploaded-version catalog.
	// +optional
	// +listType=map
	// +listMapKey=id
	AvailableVersions []CloudflareAvailableVersion `json:"availableVersions,omitempty"`
	// LiveVersion is the currently deployed version id.
	// +optional
	LiveVersion string `json:"liveVersion,omitempty"`
	// Deployment is the active rollout position.
	// +optional
	Deployment *CloudflareDeploymentStatus `json:"deployment,omitempty"`
	// Conditions use VersionFound, RolloutProgressing, RolloutComplete,
	// DriftDetected and Failed.
	// +optional
	// +listType=map
	// +listMapKey=type
	Conditions []metav1.Condition `json:"conditions,omitempty"`
	// ObservedGeneration is the spec generation last reconciled.
	// +optional
	ObservedGeneration int64 `json:"observedGeneration,omitempty"`
}

// CloudflareDeploy is the Schema for the cloudflaredeploys API.
//
// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:scope=Namespaced,shortName=cfd
// +kubebuilder:printcolumn:name="Script",type=string,JSONPath=`.spec.scriptName`
// +kubebuilder:printcolumn:name="Live",type=string,JSONPath=`.status.liveVersion`
// +kubebuilder:printcolumn:name="Complete",type=string,JSONPath=`.status.conditions[?(@.type=="RolloutComplete")].status`
// +kubebuilder:printcolumn:name="Age",type=date,JSONPath=`.metadata.creationTimestamp`
type CloudflareDeploy struct {
	metav1.TypeMeta   `json:",inline"` //nolint:revive // Kubernetes API root inline tag.
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   CloudflareDeploySpec   `json:"spec,omitempty"`
	Status CloudflareDeployStatus `json:"status,omitempty"`
}

// CloudflareDeployList contains a list of CloudflareDeploy.
//
// +kubebuilder:object:root=true
type CloudflareDeployList struct {
	metav1.TypeMeta `json:",inline"` //nolint:revive // Kubernetes API root inline tag.
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []CloudflareDeploy `json:"items"`
}

var _ = SchemeBuilder.Register(&CloudflareDeploy{}, &CloudflareDeployList{})
