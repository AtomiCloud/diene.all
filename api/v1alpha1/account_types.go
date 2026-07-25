package v1alpha1

import metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

// AccountFinalizer guards Account deletion.
const AccountFinalizer = "boron.atomi.cloud/account-finalizer"

// SecretNameReference names an object in the referent's own namespace.
type SecretNameReference struct {
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=253
	Name string `json:"name"`
}

// AccountSpec binds one Cloudflare account credential — credentials live HERE,
// once. The token is consumed via the platform SecretStore chain (cobalt
// ClusterSecretStore → carbon platform SecretStore) and referenced by Secret
// name only. There is deliberately no inline/static token field.
type AccountSpec struct {
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=64
	AccountID string `json:"accountId"`
	// +kubebuilder:validation:Required
	APITokenSecretRef SecretNameReference `json:"apiTokenSecretRef"`
}

// AccountStatus reports credential validation: TokenValid · Ready.
type AccountStatus struct {
	// +optional
	// +listType=map
	// +listMapKey=type
	Conditions []metav1.Condition `json:"conditions,omitempty"`
	// +optional
	ObservedGeneration int64 `json:"observedGeneration,omitempty"`
}

// Account is the CF account binding validated and rotated exactly once per
// Account; multiple Tunnels share one Account.
//
// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:scope=Namespaced,shortName=ba
// +kubebuilder:printcolumn:name="Token Valid",type=string,JSONPath=`.status.conditions[?(@.type=="TokenValid")].status`
// +kubebuilder:printcolumn:name="Ready",type=string,JSONPath=`.status.conditions[?(@.type=="Ready")].status`
// +kubebuilder:printcolumn:name="Age",type=date,JSONPath=`.metadata.creationTimestamp`
type Account struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`
	Spec              AccountSpec   `json:"spec,omitempty"`
	Status            AccountStatus `json:"status,omitempty"`
}

// AccountList contains a list of Account.
//
// +kubebuilder:object:root=true
type AccountList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []Account `json:"items"`
}

var _ = SchemeBuilder.Register(&Account{}, &AccountList{})
