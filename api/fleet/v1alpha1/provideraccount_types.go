package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// ProviderAccountQuotaSpec is one onboarding prerequisite ceiling for the
// account. Ceilings are checked at account onboarding, and again per row at
// reconcile, so a provider ceiling surfaces as a condition before the vendor
// hard-rejects.
type ProviderAccountQuotaSpec struct {
	// Resource is the vendor-side resource the ceiling applies to.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=63
	// +kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
	Resource string `json:"resource"`

	// Limit is the account's ceiling for Resource.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:Minimum=0
	Limit int64 `json:"limit"`

	// Region scopes the ceiling when the vendor applies it per region. Absent
	// means the ceiling is account-wide.
	// +optional
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=63
	// +kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
	Region string `json:"region,omitempty"`
}

// ProviderAccountSpec is the desired state of a ProviderAccount.
//
// ProviderAccount is SCHEMA-ONLY in this operator. Instances are rendered by
// the platform home's primordial chart; the dependency controller READS the
// registry at reconcile to resolve an explicitly named account. There is no
// reconciler, no status writer, and no auto-creation — this kind exists so the
// chart that carries the fleet registry's CRD set also carries this one.
//
// This CR carries NO credential source or path. One ProviderAccount names a
// vendor/account context only; the account's credential lives in Infisical at a
// path that VARIES by the consuming module's runtime coordinate
// (platform/landscape/class) and is therefore not a property of the account.
// The dependency consumer derives the S10 pointer solely from that runtime
// coordinate plus this account's vendor/name — see the F4 pure resolver
// (`lib/operator/provideraccount`.CredentialPointerPath) — and never reads a
// credential field from this CR, because none exists. Exposing an independent
// credential source/path here would admit a second, forgeable source of truth
// that could disagree with the derived pointer, so it is deliberately absent.
//
// Two uniqueness laws govern the registry and neither is expressible in CRD
// validation, because both span objects: `name` is unique within one vendor,
// and the pair (vendor, name) is unique fleet-wide. The reading controller
// validates the registry it watches and refuses an ambiguous resolution rather
// than inferring one; account selection is ALWAYS explicit and is never derived
// from a landscape's tier.
type ProviderAccountSpec struct {
	// Vendor is the provider this account belongs to. The vocabulary is
	// deliberately open: it spans data vendors, cloud providers, and the fleet's
	// own natively multi-tenant services consumed through a management API.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=63
	// +kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
	Vendor string `json:"vendor"`

	// Name is the account's registry name, unique within Vendor. A declaring
	// module selects this account by naming it explicitly.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=63
	// +kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
	Name string `json:"name"`

	// Plan is the vendor-side plan of this account, where the vendor applies a
	// plan account-wide and therefore forces separate named accounts instead of
	// one account split by tier.
	// +optional
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=63
	// +kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
	Plan string `json:"plan,omitempty"`

	// Quotas are the account's onboarding prerequisite ceilings.
	// +optional
	// +kubebuilder:validation:MaxItems=64
	// +listType=atomic
	Quotas []ProviderAccountQuotaSpec `json:"quotas,omitempty"`
}

// ProviderAccountStatus is the observed state of a ProviderAccount.
//
// NOTHING WRITES IT. There is no ProviderAccount reconciler anywhere in this
// operator; the subresource exists only so the kind matches the registry shape
// of its siblings and so a later validation surface has somewhere to report.
type ProviderAccountStatus struct {
	// Conditions follow the shared condition vocabulary.
	// +optional
	// +listType=map
	// +listMapKey=type
	Conditions []metav1.Condition `json:"conditions,omitempty"`

	// ObservedGeneration is the spec generation last observed.
	// +optional
	ObservedGeneration int64 `json:"observedGeneration,omitempty"`
}

// ProviderAccount is the Schema for the provideraccounts API.
//
// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:scope=Namespaced,shortName=pacct
// +kubebuilder:printcolumn:name="Vendor",type=string,JSONPath=`.spec.vendor`
// +kubebuilder:printcolumn:name="Account",type=string,JSONPath=`.spec.name`
// +kubebuilder:printcolumn:name="Plan",type=string,JSONPath=`.spec.plan`
// +kubebuilder:printcolumn:name="Age",type=date,JSONPath=`.metadata.creationTimestamp`
type ProviderAccount struct {
	metav1.TypeMeta   `json:",inline"` //nolint:revive // Kubernetes API roots require the ",inline" json tag; revive's struct-tag rule does not recognise it.
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   ProviderAccountSpec   `json:"spec,omitempty"`
	Status ProviderAccountStatus `json:"status,omitempty"`
}

// ProviderAccountList contains a list of ProviderAccount.
//
// +kubebuilder:object:root=true
type ProviderAccountList struct {
	metav1.TypeMeta `json:",inline"` //nolint:revive // Kubernetes API roots require the ",inline" json tag; revive's struct-tag rule does not recognise it.
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []ProviderAccount `json:"items"`
}

var _ = SchemeBuilder.Register(&ProviderAccount{}, &ProviderAccountList{})
