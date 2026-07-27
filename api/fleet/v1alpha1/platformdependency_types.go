package v1alpha1

import (
	"bytes"
	"fmt"
	"math"
	"strconv"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/util/intstr"
)

// DependencyComputeUnit preserves Neon's decimal JSON-number wire contract
// without asking controller-gen to emit a dangerous Go float type.
//
// +kubebuilder:validation:Type=number
type DependencyComputeUnit string

// MarshalJSON emits a finite decimal as a JSON number, never a quoted string.
func (u DependencyComputeUnit) MarshalJSON() ([]byte, error) {
	raw := string(u)
	value, err := strconv.ParseFloat(raw, 64)
	if err != nil || math.IsNaN(value) || math.IsInf(value, 0) {
		return nil, fmt.Errorf("invalid dependency compute unit %q", raw)
	}
	return []byte(raw), nil
}

// UnmarshalJSON accepts the numeric form served by the CRD. Quoted decimals
// are accepted by the Go type for defensive compatibility but admission still
// exposes a number-only schema.
func (u *DependencyComputeUnit) UnmarshalJSON(data []byte) error {
	raw := string(bytes.TrimSpace(data))
	if len(raw) >= 2 && raw[0] == '"' && raw[len(raw)-1] == '"' {
		unquoted, err := strconv.Unquote(raw)
		if err != nil {
			return fmt.Errorf("unquote dependency compute unit: %w", err)
		}
		raw = unquoted
	}
	value, err := strconv.ParseFloat(raw, 64)
	if err != nil || math.IsNaN(value) || math.IsInf(value, 0) {
		return fmt.Errorf("invalid dependency compute unit %q", raw)
	}
	*u = DependencyComputeUnit(raw)
	return nil
}

// DependencyPlacement selects the registered host that anchors a shared
// external. It never chooses a realization type.
type DependencyPlacement struct {
	// PreferredHost is the host whose region anchors a vlandscape external.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=63
	// +kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
	PreferredHost string `json:"preferredHost"`
}

// DependencyDeletionPolicy retains a removed module's Secret pointer for a
// bounded grace period after the external has been deleted.
type DependencyDeletionPolicy struct {
	// RetainSecret is a Go-style duration such as 168h.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:Pattern=`^[0-9]+(ns|us|ms|s|m|h)$`
	RetainSecret string `json:"retainSecret"`
}

// DependencyAccountSelector is the original named-account spelling retained
// for consumer compatibility. ProviderAccountRef is the canonical reference.
type DependencyAccountSelector struct {
	// Name is unique within the selected vendor.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=63
	// +kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
	Name string `json:"name"`
}

// DependencyBackup declares the cross-vendor backup obligation.
type DependencyBackup struct {
	// CrossVendor requires the recovery copy to leave the primary vendor.
	// +kubebuilder:validation:Required
	CrossVendor bool `json:"crossVendor"`
}

// DependencyParentCoordinate is a credential-free LPSM coordinate. Fork
// adapters resolve it by deterministic external name; it is never a CR ref.
type DependencyParentCoordinate struct {
	// Platform is the parent platform.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=63
	// +kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
	Platform string `json:"platform"`

	// Landscape is the parent host or virtual landscape.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=63
	// +kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
	Landscape string `json:"landscape"`

	// Service is the parent service.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=63
	// +kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
	Service string `json:"service"`

	// Module is the parent's logical module name.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=63
	// +kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
	Module string `json:"module"`
}

// DependencyAutoscale carries Neon's compute-unit range.
type DependencyAutoscale struct {
	// MinCU is the lower autoscaling bound.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:Minimum=0
	MinCU DependencyComputeUnit `json:"minCu"`

	// MaxCU is the upper autoscaling bound.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:Minimum=0
	MaxCU DependencyComputeUnit `json:"maxCu"`
}

// NeonDependencyEngine contains Neon-specific project settings.
type NeonDependencyEngine struct {
	// Tier is the named Neon plan/tier.
	// +kubebuilder:validation:Optional
	// +kubebuilder:validation:MinLength=1
	Tier string `json:"tier,omitempty"`

	// Autoscale is the optional compute-unit range.
	// +kubebuilder:validation:Optional
	Autoscale *DependencyAutoscale `json:"autoscale,omitempty"`
}

// ForkDependencyEngine contains the common first-class fork grammar.
type ForkDependencyEngine struct {
	// TTL is the renewable allocation lifetime.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:Pattern=`^[0-9]+(ns|us|ms|s|m|h)$`
	TTL string `json:"ttl"`

	// Parent is the credential-free LPSM coordinate of the source module.
	// +kubebuilder:validation:Required
	Parent DependencyParentCoordinate `json:"parent"`
}

// DragonflyDependencyEngine distinguishes snapshot-durable KV instances from
// ephemeral cache instances without adding another realization selector.
type DragonflyDependencyEngine struct {
	// Snapshot enables the upstream snapshot durability used for local KV.
	// +kubebuilder:validation:Optional
	Snapshot bool `json:"snapshot,omitempty"`
}

// EmptyDependencyEngine is a typed engine key whose v1 contract has no
// provider-specific override fields yet.
type EmptyDependencyEngine struct{}

// DependencyEngine is a typed union. Exactly one key must be present and its
// key must equal the module's explicit type discriminator.
type DependencyEngine struct {
	// Neon configures a Neon project.
	// +kubebuilder:validation:Optional
	Neon *NeonDependencyEngine `json:"neon,omitempty"`
	// NeonFork configures a broker-created Neon branch.
	// +kubebuilder:validation:Optional
	NeonFork *ForkDependencyEngine `json:"neon-fork,omitempty"`
	// CNPG selects the local CNPG realization.
	// +kubebuilder:validation:Optional
	CNPG *EmptyDependencyEngine `json:"cnpg,omitempty"`
	// Upstash configures a managed Upstash database.
	// +kubebuilder:validation:Optional
	Upstash *EmptyDependencyEngine `json:"upstash,omitempty"`
	// UpstashFork configures a broker-created Upstash restore fork.
	// +kubebuilder:validation:Optional
	UpstashFork *ForkDependencyEngine `json:"upstash-fork,omitempty"`
	// Dragonfly configures a local or replicated Dragonfly instance.
	// +kubebuilder:validation:Optional
	Dragonfly *DragonflyDependencyEngine `json:"dragonfly,omitempty"`
	// Tigris configures a managed snapshot-enabled Tigris bucket.
	// +kubebuilder:validation:Optional
	Tigris *EmptyDependencyEngine `json:"tigris,omitempty"`
	// TigrisFork configures a native Tigris CoW fork.
	// +kubebuilder:validation:Optional
	TigrisFork *ForkDependencyEngine `json:"tigris-fork,omitempty"`
	// R2 configures a Cloudflare R2 bucket.
	// +kubebuilder:validation:Optional
	R2 *EmptyDependencyEngine `json:"r2,omitempty"`
	// S3 configures an S3 bucket.
	// +kubebuilder:validation:Optional
	S3 *EmptyDependencyEngine `json:"s3,omitempty"`
	// MinIO configures a Garden-local MinIO bucket.
	// +kubebuilder:validation:Optional
	MinIO *EmptyDependencyEngine `json:"minio,omitempty"`
	// SES configures AWS SES sending.
	// +kubebuilder:validation:Optional
	SES *EmptyDependencyEngine `json:"ses,omitempty"`
	// CFEmailSending configures Cloudflare Email Sending.
	// +kubebuilder:validation:Optional
	CFEmailSending *EmptyDependencyEngine `json:"cf-email-sending,omitempty"`
	// Mailpit configures the credential-free local mail sink.
	// +kubebuilder:validation:Optional
	Mailpit *EmptyDependencyEngine `json:"mailpit,omitempty"`
}

// PlatformDependencyModuleSpec is the flat realization-independent module
// core plus the explicit type and typed engine union.
//
// +kubebuilder:validation:XValidation:rule="has(self.engine.neon) == (self.type == 'neon') && has(self.engine.neon__dash__fork) == (self.type == 'neon-fork') && has(self.engine.cnpg) == (self.type == 'cnpg') && has(self.engine.upstash) == (self.type == 'upstash') && has(self.engine.upstash__dash__fork) == (self.type == 'upstash-fork') && has(self.engine.dragonfly) == (self.type == 'dragonfly') && has(self.engine.tigris) == (self.type == 'tigris') && has(self.engine.tigris__dash__fork) == (self.type == 'tigris-fork') && has(self.engine.r2) == (self.type == 'r2') && has(self.engine.s3) == (self.type == 's3') && has(self.engine.minio) == (self.type == 'minio') && has(self.engine.ses) == (self.type == 'ses') && has(self.engine.cf__dash__email__dash__sending) == (self.type == 'cf-email-sending') && has(self.engine.mailpit) == (self.type == 'mailpit')",message="exactly one engine key must be present and equal type"
// +kubebuilder:validation:XValidation:rule="self.type in ['neon','neon-fork','upstash','upstash-fork','tigris','tigris-fork','r2','s3','ses','cf-email-sending'] ? self.delivery == 'external' : self.type in ['cnpg','minio','mailpit'] ? self.delivery == 'local' : self.type == 'dragonfly' ? self.delivery in ['local','replicated'] : false",message="delivery is not legal for the selected type"
// +kubebuilder:validation:XValidation:rule="(self.delivery == 'external' && has(self.providerAccountRef)) || (self.delivery != 'external' && !has(self.providerAccountRef) && !has(self.account))",message="external modules require providerAccountRef and local or replicated modules cannot select an account"
// +kubebuilder:validation:XValidation:rule="!has(self.account) || !has(self.providerAccountRef) || self.account.name == self.providerAccountRef",message="account.name and providerAccountRef must agree when both are present"
type PlatformDependencyModuleSpec struct {
	// Type is the sole realization selector.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:Enum=neon;neon-fork;cnpg;upstash;upstash-fork;dragonfly;tigris;tigris-fork;r2;s3;minio;ses;cf-email-sending;mailpit
	Type string `json:"type"`

	// Delivery selects vendor, direct local, or ApplicationSet realization.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:Enum=external;local;replicated
	Delivery string `json:"delivery"`

	// Account is the legacy named-account spelling. If present it must agree
	// with ProviderAccountRef.
	// +kubebuilder:validation:Optional
	Account *DependencyAccountSelector `json:"account,omitempty"`

	// ProviderAccountRef names the ProviderAccount for an external type.
	// +kubebuilder:validation:Optional
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=63
	// +kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
	ProviderAccountRef string `json:"providerAccountRef,omitempty"`

	// CredentialMode declares whether the application receives credentials.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:Enum=standard;none
	CredentialMode string `json:"credentialMode"`

	// Rotation is the explicit registered-fleet rotation knob.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:Enum=on;off
	Rotation string `json:"rotation"`

	// CPU is a quantity-like string or numeric CPU count.
	// +kubebuilder:validation:Optional
	CPU intstr.IntOrString `json:"cpu,omitempty"`

	// RAM is a Kubernetes-style quantity.
	// +kubebuilder:validation:Optional
	// +kubebuilder:validation:MinLength=1
	RAM string `json:"ram,omitempty"`

	// Storage is a Kubernetes-style quantity.
	// +kubebuilder:validation:Optional
	// +kubebuilder:validation:MinLength=1
	Storage string `json:"storage,omitempty"`

	// Version is the requested engine version.
	// +kubebuilder:validation:Optional
	// +kubebuilder:validation:MinLength=1
	Version string `json:"version,omitempty"`

	// Backup declares the hard cross-vendor recovery obligation.
	// +kubebuilder:validation:Optional
	Backup *DependencyBackup `json:"backup,omitempty"`

	// Engine carries exactly the selected type's provider-specific settings.
	// +kubebuilder:validation:Required
	Engine DependencyEngine `json:"engine"`

	// Adopt explicitly permits rebinding to a changed backing identity.
	// +kubebuilder:validation:Optional
	Adopt bool `json:"adopt,omitempty"`
}

// PlatformDependencySpec is the desired state of a row or one shared
// platform-by-vlandscape declaration.
//
// Landscape classification and per-landscape realization legality are
// registry facts checked at reconcile time. That policy includes preview
// Mailpit-only email, the ditto SES sandbox carve-out, Garden consumption of
// remote forks, and Dragonfly local in Garden versus replicated on registered
// production landscapes. Account existence and permissions, envelope
// membership, preferred-host validity, and cluster multiplicity are likewise
// reconcile-time ERROR conditions because CRD CEL cannot query the registry.
type PlatformDependencySpec struct {
	// Platform is the declaring platform.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=63
	// +kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
	Platform string `json:"platform"`

	// Service is present for service-row declarations and absent for a
	// platform-shared declaration rendered by the platform home.
	// +kubebuilder:validation:Optional
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=63
	// +kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
	Service string `json:"service,omitempty"`

	// Landscape may name a registered host, a vlandscape, or a Garden profile.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=63
	// +kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
	Landscape string `json:"landscape"`

	// Placement anchors shared externals without selecting their type.
	// +kubebuilder:validation:Optional
	Placement *DependencyPlacement `json:"placement,omitempty"`

	// Database holds postgres modules.
	// +kubebuilder:validation:Optional
	// +kubebuilder:validation:MaxProperties=128
	// +kubebuilder:validation:XValidation:rule="self.all(k, m, m.type in ['neon','neon-fork','cnpg'])",message="database modules must use a database type"
	Database map[string]PlatformDependencyModuleSpec `json:"database,omitempty"`

	// KV holds persistent key-value modules.
	// +kubebuilder:validation:Optional
	// +kubebuilder:validation:MaxProperties=128
	// +kubebuilder:validation:XValidation:rule="self.all(k, m, m.type in ['upstash','upstash-fork','dragonfly'])",message="kv modules must use a kv type"
	KV map[string]PlatformDependencyModuleSpec `json:"kv,omitempty"`

	// Cache holds ephemeral Dragonfly modules.
	// +kubebuilder:validation:Optional
	// +kubebuilder:validation:MaxProperties=128
	// +kubebuilder:validation:XValidation:rule="self.all(k, m, m.type == 'dragonfly')",message="cache modules must use dragonfly"
	Cache map[string]PlatformDependencyModuleSpec `json:"cache,omitempty"`

	// Store holds object-storage modules.
	// +kubebuilder:validation:Optional
	// +kubebuilder:validation:MaxProperties=128
	// +kubebuilder:validation:XValidation:rule="self.all(k, m, m.type in ['tigris','tigris-fork','r2','s3','minio'])",message="store modules must use a store type"
	Store map[string]PlatformDependencyModuleSpec `json:"store,omitempty"`

	// Email holds the platform-scoped sender or local sink.
	// +kubebuilder:validation:Optional
	// +kubebuilder:validation:MaxProperties=128
	// +kubebuilder:validation:XValidation:rule="self.all(k, m, m.type in ['ses','cf-email-sending','mailpit'])",message="email modules must use an email type"
	Email map[string]PlatformDependencyModuleSpec `json:"email,omitempty"`

	// DeletionPolicy controls the post-delete Secret-pointer grace. The API
	// defaults an omitted policy to retain the pointer for 168h.
	// +kubebuilder:validation:Optional
	// +kubebuilder:default={retainSecret: "168h"}
	DeletionPolicy *DependencyDeletionPolicy `json:"deletionPolicy,omitempty"`
}

// PlatformDependencyForkStatus contains only allocation identifiers and a
// Secret reference; no connection string, password, or token may appear here.
type PlatformDependencyForkStatus struct {
	// AllocationID is the durable reaper allocation identifier.
	// +optional
	AllocationID string `json:"allocationId,omitempty"`
	// ExternalID is unique within the named provider account.
	// +optional
	ExternalID string `json:"externalId,omitempty"`
	// Generation fences compare-and-release cleanup.
	// +optional
	Generation int64 `json:"generation,omitempty"`
	// Owner is the non-secret allocation owner identity.
	// +optional
	Owner string `json:"owner,omitempty"`
	// ExpiresAt is the renewable TTL deadline.
	// +optional
	ExpiresAt *metav1.Time `json:"expiresAt,omitempty"`
	// SecretRef names the controller-owned cluster-local result Secret.
	// +optional
	SecretRef string `json:"secretRef,omitempty"`
}

// PlatformDependencyModuleStatus is isolated per logical module.
type PlatformDependencyModuleStatus struct {
	// Phase is the module's level-triggered lifecycle phase.
	// +optional
	Phase string `json:"phase,omitempty"`
	// ExternalID is unique within the module's named provider account.
	// +optional
	ExternalID string `json:"externalId,omitempty"`
	// SecretPathOrRef is a pointer/reference and never secret material.
	// +optional
	SecretPathOrRef string `json:"secretPathOrRef,omitempty"`
	// Fork is populated only for a first-class fork type.
	// +optional
	Fork *PlatformDependencyForkStatus `json:"fork,omitempty"`
	// Conditions include Provisioned, SecretWritten, Conflict, Unresolved,
	// NotInEnvelope, SecretRetained, DeclarerChanged, ForkUnsupported and Ready.
	// +optional
	// +listType=map
	// +listMapKey=type
	Conditions []metav1.Condition `json:"conditions,omitempty"`
}

// PlatformDependencyStatus is the observed state of a PlatformDependency.
type PlatformDependencyStatus struct {
	// Modules is a map so one module's conditions cannot overwrite another's.
	// +optional
	Modules map[string]PlatformDependencyModuleStatus `json:"modules,omitempty"`
	// Conditions are declaration-wide conditions such as Conflict and Ready.
	// +optional
	// +listType=map
	// +listMapKey=type
	Conditions []metav1.Condition `json:"conditions,omitempty"`
	// ObservedGeneration is the spec generation last reconciled.
	// +optional
	ObservedGeneration int64 `json:"observedGeneration,omitempty"`
}

// PlatformDependency is the Schema for the platformdependencies API.
//
// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:scope=Namespaced,shortName=pdep
// +kubebuilder:printcolumn:name="Platform",type=string,JSONPath=`.spec.platform`
// +kubebuilder:printcolumn:name="Landscape",type=string,JSONPath=`.spec.landscape`
// +kubebuilder:printcolumn:name="Ready",type=string,JSONPath=`.status.conditions[?(@.type=="Ready")].status`
// +kubebuilder:printcolumn:name="Age",type=date,JSONPath=`.metadata.creationTimestamp`
type PlatformDependency struct {
	metav1.TypeMeta   `json:",inline"` //nolint:revive // Kubernetes API root inline tag.
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   PlatformDependencySpec   `json:"spec,omitempty"`
	Status PlatformDependencyStatus `json:"status,omitempty"`
}

// PlatformDependencyList contains a list of PlatformDependency.
//
// +kubebuilder:object:root=true
type PlatformDependencyList struct {
	metav1.TypeMeta `json:",inline"` //nolint:revive // Kubernetes API root inline tag.
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []PlatformDependency `json:"items"`
}

var _ = SchemeBuilder.Register(&PlatformDependency{}, &PlatformDependencyList{})
