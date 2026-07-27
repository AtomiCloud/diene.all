package v1alpha1

import metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

// WebhookEngineHome is the immutable vlandscape home of an internal tenant.
type WebhookEngineHome struct {
	// VLandscape is immutable because moving intake requires a new tenant and
	// an explicit cutover.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=63
	// +kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
	// +kubebuilder:validation:XValidation:rule="self == oldSelf",message="home.vlandscape is immutable"
	VLandscape string `json:"vlandscape"`
}

// WebhookArchive configures archive-before-drop retention.
type WebhookArchive struct {
	// Store is the ruled archive store class.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:Enum=tigris
	Store string `json:"store"`
	// Bucket is the Tigris bucket name.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=63
	// +kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
	Bucket string `json:"bucket"`
}

// WebhookRetention configures monthly live streams and archive-before-drop.
type WebhookRetention struct {
	// Cycle is fixed to monthly in v1.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:Enum=monthly
	Cycle string `json:"cycle"`
	// KeepMonths is the number of month streams retained live.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:Minimum=1
	// +kubebuilder:validation:Maximum=120
	KeepMonths int32 `json:"keepMonths"`
	// Archive identifies the archive-before-drop store.
	// +kubebuilder:validation:Required
	Archive WebhookArchive `json:"archive"`
}

// WebhookBackoff configures independent endpoint retries.
type WebhookBackoff struct {
	// Initial is the first retry delay.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:Pattern=`^[0-9]+(ns|us|ms|s|m|h)$`
	Initial string `json:"initial"`
	// Shape is the seconds-to-minutes-to-hours curve.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:Enum=exponential
	Shape string `json:"shape"`
}

// WebhookCircuitBreaker configures continuous-failure isolation.
type WebhookCircuitBreaker struct {
	// FailWindow is the failure duration before the endpoint circuit opens.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:Pattern=`^[0-9]+(ns|us|ms|s|m|h)$`
	FailWindow string `json:"failWindow"`
}

// WebhookQuotas configures in-app intake enforcement.
type WebhookQuotas struct {
	// IntakeRPS is the sustained per-tenant intake rate.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:Minimum=1
	IntakeRPS int32 `json:"intakeRps"`
	// Burst is the permitted burst size.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:Minimum=1
	Burst int32 `json:"burst"`
}

// WebhookEngineSpec is management/config intent only. It deliberately has no
// Worker, D1, KV, version, engine-version, or deployment fields: mercury owns
// its runtime and is configured through its product management API.
type WebhookEngineSpec struct {
	// Home binds this internal tenant immutably to a vlandscape.
	// +kubebuilder:validation:Required
	Home WebhookEngineHome `json:"home"`
	// Retention configures monthly live streams and archive-before-drop.
	// +kubebuilder:validation:Required
	Retention WebhookRetention `json:"retention"`
	// RetryWindow is the maximum independent endpoint retry duration.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:Pattern=`^[0-9]+(ns|us|ms|s|m|h)$`
	RetryWindow string `json:"retryWindow"`
	// Backoff is the retry curve.
	// +kubebuilder:validation:Required
	Backoff WebhookBackoff `json:"backoff"`
	// CircuitBreaker isolates a continuously failing endpoint.
	// +kubebuilder:validation:Required
	CircuitBreaker WebhookCircuitBreaker `json:"circuitBreaker"`
	// DedupWindow is the v1 deduplication horizon.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:Pattern=`^[0-9]+(ns|us|ms|s|m|h)$`
	DedupWindow string `json:"dedupWindow"`
	// Quotas are enforced in mercury itself.
	// +kubebuilder:validation:Required
	Quotas WebhookQuotas `json:"quotas"`
	// CustomDomains is registered state, not a CNAME-only declaration.
	// +kubebuilder:validation:Optional
	// +kubebuilder:validation:MaxItems=64
	// +listType=set
	// +kubebuilder:validation:items:MinLength=1
	// +kubebuilder:validation:items:MaxLength=253
	CustomDomains []string `json:"customDomains,omitempty"`
}

// WebhookLandscapeStatus mirrors mercury's compilation acknowledgement.
type WebhookLandscapeStatus struct {
	// ConfigGeneration is the generation mercury compiled for this landscape.
	// +optional
	ConfigGeneration int64 `json:"configGeneration,omitempty"`
	// Acked reports that the serving landscape observes that generation.
	// +optional
	Acked bool `json:"acked,omitempty"`
	// Conditions isolate per-landscape compilation/ack failures.
	// +optional
	// +listType=map
	// +listMapKey=type
	Conditions []metav1.Condition `json:"conditions,omitempty"`
}

// WebhookProviderStatus records route use and last-known orphan grace.
type WebhookProviderStatus struct {
	// RouteCount is the number of live routes using this provider config.
	// +optional
	RouteCount int32 `json:"routeCount,omitempty"`
	// Orphaned keeps last-known verification config through retention.
	// +optional
	Orphaned bool `json:"orphaned,omitempty"`
	// Conditions include OrphanedProvider.
	// +optional
	// +listType=map
	// +listMapKey=type
	Conditions []metav1.Condition `json:"conditions,omitempty"`
}

// WebhookEngineStatus is the observed internal-tenant configuration state.
type WebhookEngineStatus struct {
	// Landscapes mirrors mercury config generations and acknowledgements.
	// +optional
	Landscapes map[string]WebhookLandscapeStatus `json:"landscapes,omitempty"`
	// Providers tracks route count and orphan grace per provider.
	// +optional
	Providers map[string]WebhookProviderStatus `json:"providers,omitempty"`
	// Conditions include ConfigCompiled, SecretsFanned, HomeChangeBlocked,
	// TargetNotServed, Conflict, TenantProvisioned, OrphanedProvider and Ready.
	// +optional
	// +listType=map
	// +listMapKey=type
	Conditions []metav1.Condition `json:"conditions,omitempty"`
	// ObservedGeneration is the spec generation last reconciled.
	// +optional
	ObservedGeneration int64 `json:"observedGeneration,omitempty"`
}

// WebhookEngine is the Schema for the webhookengines API.
//
// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:scope=Namespaced,shortName=wheng
// +kubebuilder:printcolumn:name="Home",type=string,JSONPath=`.spec.home.vlandscape`
// +kubebuilder:printcolumn:name="Ready",type=string,JSONPath=`.status.conditions[?(@.type=="Ready")].status`
// +kubebuilder:printcolumn:name="Age",type=date,JSONPath=`.metadata.creationTimestamp`
type WebhookEngine struct {
	metav1.TypeMeta   `json:",inline"` //nolint:revive // Kubernetes API root inline tag.
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   WebhookEngineSpec   `json:"spec,omitempty"`
	Status WebhookEngineStatus `json:"status,omitempty"`
}

// WebhookEngineList contains a list of WebhookEngine.
//
// +kubebuilder:object:root=true
type WebhookEngineList struct {
	metav1.TypeMeta `json:",inline"` //nolint:revive // Kubernetes API root inline tag.
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []WebhookEngine `json:"items"`
}

var _ = SchemeBuilder.Register(&WebhookEngine{}, &WebhookEngineList{})
