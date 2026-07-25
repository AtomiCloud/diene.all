package boron

// Condition is a pure, k8s-free condition intent. Adapters translate it into a
// metav1.Condition on the CR status.
type Condition struct {
	Type    string
	Status  string
	Reason  string
	Message string
}

// Standard condition status values.
const (
	StatusTrue  = "True"
	StatusFalse = "False"
)

// Condition type vocabulary for the three Boron CRDs (goals/charts/boron.md §CRDs).
// Every type here is ArgoCD-Lua gateable: True/False with a stable reason.
const (
	// Account conditions.
	TypeTokenValid = "TokenValid"
	TypeReady      = "Ready"

	// Tunnel conditions.
	TypeAccountNotReady = "AccountNotReady"
	TypeConfigSynced    = "ConfigSynced"
	TypeReplicasReady   = "ReplicasReady"

	// Exposure conditions.
	TypeAccepted     = "Accepted"
	TypeResolvedRefs = "ResolvedRefs"
	TypeProgrammed   = "Programmed"
	TypeConflicted   = "Conflicted"
)

// Condition reasons (stable refusal vocabulary from the goal document).
const (
	ReasonTokenValidated         = "TokenValidated"
	ReasonTokenInvalid           = "TokenInvalid"
	ReasonSecretMissing          = "SecretMissing"
	ReasonProviderUnreachable    = "ProviderUnreachable"
	ReasonAccountReady           = "AccountReady"
	ReasonAccountNotReady        = "AccountNotReady"
	ReasonConfigSynced           = "ConfigSynced"
	ReasonConfigPushFailed       = "ConfigPushFailed"
	ReasonReplicasReady          = "ReplicasReady"
	ReasonReplicasPending        = "ReplicasPending"
	ReasonAccepted               = "Accepted"
	ReasonProfileUnsupported     = "ProfileUnsupported"
	ReasonCoordinatesMismatch    = "CoordinatesMismatch"
	ReasonTunnelMissing          = "TunnelMissing"
	ReasonUnsupportedMatch       = "UnsupportedMatch"
	ReasonUnsupportedTLSCoverage = "UnsupportedTLSCoverage"
	ReasonPolicyMissing          = "PolicyMissing"
	ReasonBackendNotFound        = "BackendNotFound"
	ReasonSharedBackendDenied    = "SharedBackendDenied"
	ReasonResolvedRefs           = "ResolvedRefs"
	ReasonProgrammed             = "Programmed"
	ReasonProgrammingPending     = "ProgrammingPending"
	ReasonHostnameConflict       = "HostnameConflict"
	ReasonNoConflict             = "NoConflict"
	ReasonAccessAppAdopted       = "AccessAppAdopted"
)
