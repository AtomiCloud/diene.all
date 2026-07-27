package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// Cluster provisioning phases. The state machine is
// provisioning -> ready -> decommissioned; destruction is always a separate
// explicit act and is never implied by leaving the answer set.
const (
	// ClusterPhaseProvisioning means the provider-side cluster is being created.
	ClusterPhaseProvisioning = "provisioning"
	// ClusterPhaseReady means the cluster is provisioned and serving.
	ClusterPhaseReady = "ready"
	// ClusterPhaseDecommissioned means the cluster completed a Decommission flow.
	ClusterPhaseDecommissioned = "decommissioned"
)

// Fixed-IP guarantee classes. The class records what the provider actually
// guarantees about an address, because the three providers differ: a true
// reserved IP survives load-balancer deletion, a pre-allocated elastic IP
// survives it too, and a load-balancer-lifetime address does not (the operating
// invariant there is to never delete the load balancer).
const (
	// GuaranteeClassReserved is a provider-reserved address surviving LB deletion.
	GuaranteeClassReserved = "reserved"
	// GuaranteeClassEIP is a pre-allocated elastic IP surviving LB deletion.
	GuaranteeClassEIP = "eip"
	// GuaranteeClassLBLifetime is an address bound to the load balancer's life.
	GuaranteeClassLBLifetime = "lb-lifetime"
)

// ClusterHostRoleAnonymousVclusterHost is the only declared host role. It marks
// the registration that carries hosted-development substrate rather than fleet
// workloads; its traffic dial is invariantly false.
const ClusterHostRoleAnonymousVclusterHost = "anonymous-vcluster-host"

// ClusterOriginModeLoadBalancer is the fleet-wide public origin mode: every
// serving cluster sits behind a provider cloud load balancer.
const ClusterOriginModeLoadBalancer = "loadbalancer"

// ClusterRegistrationSpec is the desired state of a ClusterRegistration.
//
// A physical cluster is identified by (landscape x mark). Provisioning runs
// through direct provider APIs and is ledger-backed; deletion is refused while
// anything still references the registration.
type ClusterRegistrationSpec struct {
	// Landscape is the Landscape this cluster belongs to. Its Argo cluster-Secret
	// label is the sole membership truth for replicated delivery.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=63
	// +kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
	Landscape string `json:"landscape"`

	// Mark distinguishes the clusters of one landscape from each other.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=63
	// +kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
	Mark string `json:"mark"`

	// Provider selects the direct provider API the cluster controller drives.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:Enum=doks;eks;oke
	Provider string `json:"provider"`

	// OriginMode is the public origin shape. It is fleet-wide loadbalancer.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:Enum=loadbalancer
	// +kubebuilder:default=loadbalancer
	OriginMode string `json:"originMode"`

	// Traffic is the EXPLICIT answer-set dial and the canary/cutover control:
	// false leaves the A-set while the cluster keeps running, true joins it.
	// It is never a destruction signal. It is required rather than defaulted so
	// that joining the fleet's live answer set is always a declared act.
	// +kubebuilder:validation:Required
	Traffic bool `json:"traffic"`

	// HostRole narrows what the registration carries. The only declared value is
	// anonymous-vcluster-host; absent means an ordinary workload cluster.
	// +optional
	// +kubebuilder:validation:Enum=anonymous-vcluster-host
	HostRole string `json:"hostRole,omitempty"`
}

// LoadBalancerIP is one fixed ingress address of a registered cluster together
// with the guarantee the provider makes about it.
type LoadBalancerIP struct {
	// IP is the address itself.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=45
	IP string `json:"ip"`

	// GuaranteeClass records what survives a load-balancer deletion.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:Enum=reserved;eip;lb-lifetime
	GuaranteeClass string `json:"guaranteeClass"`
}

// ClusterRegistrationStatus is the observed state of a ClusterRegistration.
type ClusterRegistrationStatus struct {
	// Phase is the provisioning state machine position.
	// +optional
	// +kubebuilder:validation:Enum=provisioning;ready;decommissioned
	Phase string `json:"phase,omitempty"`

	// AcceptingTraffic is stamped by the traffic controller's unified poll loop
	// from the cluster's own gateway probe. It is an observation, not a dial:
	// the dial is spec.traffic.
	// +optional
	AcceptingTraffic bool `json:"acceptingTraffic,omitempty"`

	// LBIPs records the cluster's fixed ingress addresses per guarantee class.
	// +optional
	// +listType=map
	// +listMapKey=ip
	LBIPs []LoadBalancerIP `json:"lbIPs,omitempty"`

	// ArgoSecret points at the Argo cluster Secret this registration owns, in
	// namespace/name form. It is the only registry-to-Argo interface, and it is
	// a pointer: no credential material is ever mirrored into status.
	// +optional
	// +kubebuilder:validation:MaxLength=512
	// +kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9.]*[a-z0-9])?/[a-z0-9]([-a-z0-9.]*[a-z0-9])?$`
	ArgoSecret string `json:"argoSecret,omitempty"`

	// Conditions follow the shared condition vocabulary. QuotaExhausted is
	// first-class here: a provider ceiling is reported before the vendor hard
	// rejects, and the same ceiling is an account-onboarding prerequisite.
	// +optional
	// +listType=map
	// +listMapKey=type
	Conditions []metav1.Condition `json:"conditions,omitempty"`

	// ObservedGeneration is the spec generation last reconciled.
	// +optional
	ObservedGeneration int64 `json:"observedGeneration,omitempty"`
}

// ClusterRegistration is the Schema for the clusterregistrations API.
//
// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:scope=Cluster,shortName=creg
// +kubebuilder:printcolumn:name="Landscape",type=string,JSONPath=`.spec.landscape`
// +kubebuilder:printcolumn:name="Provider",type=string,JSONPath=`.spec.provider`
// +kubebuilder:printcolumn:name="Traffic",type=boolean,JSONPath=`.spec.traffic`
// +kubebuilder:printcolumn:name="Phase",type=string,JSONPath=`.status.phase`
// +kubebuilder:printcolumn:name="Accepting",type=boolean,JSONPath=`.status.acceptingTraffic`
// +kubebuilder:printcolumn:name="Age",type=date,JSONPath=`.metadata.creationTimestamp`
type ClusterRegistration struct {
	metav1.TypeMeta   `json:",inline"` //nolint:revive // Kubernetes API roots require the ",inline" json tag; revive's struct-tag rule does not recognise it.
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   ClusterRegistrationSpec   `json:"spec,omitempty"`
	Status ClusterRegistrationStatus `json:"status,omitempty"`
}

// ClusterRegistrationList contains a list of ClusterRegistration.
//
// +kubebuilder:object:root=true
type ClusterRegistrationList struct {
	metav1.TypeMeta `json:",inline"` //nolint:revive // Kubernetes API roots require the ",inline" json tag; revive's struct-tag rule does not recognise it.
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []ClusterRegistration `json:"items"`
}

var _ = SchemeBuilder.Register(&ClusterRegistration{}, &ClusterRegistrationList{})
