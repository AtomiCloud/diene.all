// Package reconcile is the pure application service for the Boron domain. It
// owns every domain and application decision — install-profile admission,
// hostname derivation, exact-host TLS preflight, policy resolution, the
// shared-backend guardrail, oldest-wins conflict determinism, and the
// all-or-nothing programming decision — and returns a pure Decision the
// controller executes. Controllers depend only on this package (plus the kube
// and cloudflare ports); they never import the decision internals
// (boron/plan/brake). The architecture gate enforces that.
//
// This package is pure domain: it imports no k8s.io/* or sigs.k8s.io/* packages.
package reconcile

import (
	"fmt"

	"github.com/AtomiCloud/diene.boron/lib/operator/boron"
	
)

// Condition re-exports the pure, k8s-free condition type so controllers depend
// only on this service.
type Condition = boron.Condition

// Re-exported condition vocabulary so controllers depend only on this service
// and never on the decision internals (the architecture gate enforces that).
const (
	TypeTokenValid      = boron.TypeTokenValid
	TypeReady           = boron.TypeReady
	TypeAccountNotReady = boron.TypeAccountNotReady
	TypeConfigSynced    = boron.TypeConfigSynced
	TypeReplicasReady   = boron.TypeReplicasReady
	TypeAccepted        = boron.TypeAccepted
	TypeResolvedRefs    = boron.TypeResolvedRefs
	TypeProgrammed      = boron.TypeProgrammed
	TypeConflicted      = boron.TypeConflicted
	StatusTrue          = boron.StatusTrue
	StatusFalse         = boron.StatusFalse
)

// Re-exported reason vocabulary used by controllers and tests.
const (
	ReasonAccessAppAdopted = boron.ReasonAccessAppAdopted
)

// Kubernetes event types the controller emits.
const (
	EventNormal  = "Normal"
	EventWarning = "Warning"
)

// Event is a reconcile outcome the controller publishes as a Kubernetes event.
type Event struct {
	Type    string
	Reason  string
	Message string
}

// Coordinates re-exports the four-slot LPSM coordinate.
type Coordinates = boron.Coordinates

// ConflictCandidate re-exports the oldest-wins conflict identity.
type ConflictCandidate = boron.ConflictCandidate

// DeriveHostname re-exports the canonical dotted hostname derivation so
// controllers never import the decision internals.
func DeriveHostname(c Coordinates, instance, zone string) string {
	return boron.Hostname(c, instance, zone)
}

// NormalizePath re-exports the path default for pre-defaulting objects.
func NormalizePath(path string) string {
	return boron.NormalizePath(path)
}

// OlderCandidate re-exports the deterministic oldest-wins ordering.
func OlderCandidate(left, right ConflictCandidate) bool {
	return boron.Older(left, right)
}

// Profile re-exports the install-profile names.
const (
	ProfileLapras     = boron.ProfileLapras
	ProfileDitto      = boron.ProfileDitto
	ProfileRegistered = boron.ProfileRegistered
)

// Installation is the trusted Garden-supplied installation identity the manager
// runs under. It is manager configuration, never CR input.
type Installation struct {
	Profile      string
	Connected    bool
	DittoEnabled bool
	// Landscape and Instance are the trusted profile metadata every Exposure's
	// declared coordinates must match.
	Landscape string
	Instance  string
}

// ─── Account ─────────────────────────────────────────────────────────────────

// AccountInput is everything the service needs to decide an Account reconcile.
type AccountInput struct {
	SecretFound  bool
	TokenPresent bool
	// TokenValid and ProviderReachable report the provider validate call.
	Checked           bool
	TokenValid        bool
	ProviderReachable bool
	ProviderMessage   string
}

// AccountDecision is the pure Account reconcile outcome.
type AccountDecision struct {
	Ready      bool
	Conditions []Condition
	Events     []Event
}

// DecideAccount validates the Account exactly once per Account: the referenced
// secret must exist and carry a token, and the provider must accept it.
func DecideAccount(in AccountInput) AccountDecision {
	switch {
	case !in.SecretFound:
		return accountRefused(boron.ReasonSecretMissing, "referenced api token secret not found")
	case !in.TokenPresent:
		return accountRefused(boron.ReasonSecretMissing, "referenced api token secret carries no token key")
	case !in.Checked || !in.ProviderReachable:
		message := in.ProviderMessage
		if message == "" {
			message = "cloudflare api unreachable"
		}
		return accountRefused(boron.ReasonProviderUnreachable, message)
	case !in.TokenValid:
		return accountRefused(boron.ReasonTokenInvalid, "cloudflare rejected the api token")
	}
	return AccountDecision{
		Ready: true,
		Conditions: []Condition{
			{Type: TypeTokenValid, Status: StatusTrue, Reason: boron.ReasonTokenValidated, Message: "cloudflare accepted the api token"},
			{Type: TypeReady, Status: StatusTrue, Reason: boron.ReasonAccountReady, Message: "account is ready"},
		},
		Events: []Event{{EventNormal, "TokenValidated", "cloudflare accepted the api token"}},
	}
}

func accountRefused(reason, message string) AccountDecision {
	return AccountDecision{
		Conditions: []Condition{
			{Type: TypeTokenValid, Status: StatusFalse, Reason: reason, Message: message},
			{Type: TypeReady, Status: StatusFalse, Reason: reason, Message: message},
		},
		Events: []Event{{EventWarning, reason, message}},
	}
}

// ─── Tunnel ──────────────────────────────────────────────────────────────────

// TunnelReplicas is the fixed cloudflared replica count. Not configurable, no HPA.
const TunnelReplicas int32 = 2

// IngressRule is one Exposure's contribution to the tunnel's remote config.
type IngressRule struct {
	Hostname string
	Path     string
	Backend  string
}

// TunnelInput is everything the service needs to decide a Tunnel reconcile.
type TunnelInput struct {
	AccountFound bool
	AccountReady bool
	// TunnelEnsured/ConfigPushed report the provider calls already attempted by
	// the controller this reconcile (false with a message when they failed).
	TunnelEnsured     bool
	ConfigPushed      bool
	ProviderMessage   string
	AvailableReplicas int32
}

// TunnelDecision is the pure Tunnel reconcile outcome.
type TunnelDecision struct {
	Conditions []Condition
	Events     []Event
}

// DecideTunnel rolls up Account readiness, the remote config-push result, and
// replica health into the Tunnel's condition set.
func DecideTunnel(in TunnelInput) TunnelDecision {
	if !in.AccountFound || !in.AccountReady {
		message := "referenced Account is not ready"
		if !in.AccountFound {
			message = "referenced Account not found"
		}
		return TunnelDecision{
			Conditions: []Condition{
				{Type: TypeAccountNotReady, Status: StatusTrue, Reason: boron.ReasonAccountNotReady, Message: message},
				{Type: TypeConfigSynced, Status: StatusFalse, Reason: boron.ReasonAccountNotReady, Message: message},
				{Type: TypeReplicasReady, Status: replicaStatus(in.AvailableReplicas), Reason: replicaReason(in.AvailableReplicas), Message: replicaMessage(in.AvailableReplicas)},
			},
			Events: []Event{{EventWarning, boron.ReasonAccountNotReady, message}},
		}
	}

	conditions := []Condition{{Type: TypeAccountNotReady, Status: StatusFalse, Reason: boron.ReasonAccountReady, Message: "referenced Account is ready"}}
	var events []Event
	if in.TunnelEnsured && in.ConfigPushed {
		conditions = append(conditions, Condition{Type: TypeConfigSynced, Status: StatusTrue, Reason: boron.ReasonConfigSynced, Message: "remote tunnel configuration is pushed and versioned"})
	} else {
		message := in.ProviderMessage
		if message == "" {
			message = "remote tunnel configuration push failed"
		}
		conditions = append(conditions, Condition{Type: TypeConfigSynced, Status: StatusFalse, Reason: boron.ReasonConfigPushFailed, Message: message})
		events = append(events, Event{EventWarning, boron.ReasonConfigPushFailed, message})
	}
	conditions = append(conditions, Condition{Type: TypeReplicasReady, Status: replicaStatus(in.AvailableReplicas), Reason: replicaReason(in.AvailableReplicas), Message: replicaMessage(in.AvailableReplicas)})
	return TunnelDecision{Conditions: conditions, Events: events}
}

func replicaStatus(available int32) string {
	if available == TunnelReplicas {
		return StatusTrue
	}
	return StatusFalse
}

func replicaReason(available int32) string {
	if available == TunnelReplicas {
		return boron.ReasonReplicasReady
	}
	return boron.ReasonReplicasPending
}

func replicaMessage(available int32) string {
	return fmt.Sprintf("%d/%d cloudflared replicas available", available, TunnelReplicas)
}

// ─── Exposure ────────────────────────────────────────────────────────────────

// ExposureInput is everything the service needs to decide an Exposure reconcile
// up to (but not including) the provider writes. The controller resolves the
// cluster and provider reads first; Decide orders them into refusals or a
// programming plan.
type ExposureInput struct {
	Installation Installation

	Coordinates Coordinates
	Instance    string
	Path        string
	Namespace   string

	TunnelFound   bool
	TunnelZone    string
	TunnelID      string
	AccountReady  bool
	AccountFound  bool

	BackendFound       bool
	BackendPortFound   bool
	BackendPublic      bool
	AllowSharedBackend bool
	BackendName        string
	BackendPort        int32

	// TLSCoverage reports the exact-host DNS/edge-TLS preflight for the derived
	// hostname (checked=true when the preflight ran).
	TLSChecked  bool
	TLSCovered  bool
	TLSMessage  string

	// Policy resolution: names requested and the subset that resolved to ids.
	PolicyNames    []string
	ResolvedPolicy map[string]string

	// Conflict: the oldest ConflictCandidate currently claiming this hostname+path
	// (zero-valued when none), and this Exposure's own identity.
	Self   ConflictCandidate
	Oldest ConflictCandidate
	HasRival bool
}

// ExposureProgram is the all-or-nothing programming plan for one Exposure.
type ExposureProgram struct {
	Hostname  string
	Path      string
	Backend   string
	PolicyIDs []string
}

// ExposureDecision is the pure Exposure reconcile outcome.
type ExposureDecision struct {
	// Program is non-nil only when every gate passed; the controller then
	// executes LIST-then-adopt, policy attach, DNS, and the ingress rule.
	Program    *ExposureProgram
	Hostname   string
	Conditions []Condition
	Events     []Event
}

// DecideExposure runs the goal's reconcile mechanics steps 2–5 and 7's ordering
// decision: admission, hostname derivation, exact-host TLS preflight (fail
// closed), ref resolution (backend + every policy), the shared-backend
// guardrail, and oldest-wins conflict determinism. ANY failure programs nothing.
func DecideExposure(in ExposureInput) ExposureDecision {
	admission := boron.AdmitProfile(in.Installation.Profile, in.Installation.Connected, in.Installation.DittoEnabled)
	if !admission.Allowed {
		return exposureRefusedAccepted(admission.Reason, admission.Message)
	}
	if !in.TunnelFound {
		return exposureRefusedAccepted(boron.ReasonTunnelMissing, "referenced Tunnel not found")
	}
	if !in.AccountFound || !in.AccountReady {
		return exposureRefusedAccepted(boron.ReasonAccountNotReady, "the Tunnel's Account is not ready")
	}
	if in.Coordinates.Platform != in.Namespace {
		return exposureRefusedAccepted(boron.ReasonCoordinatesMismatch,
			fmt.Sprintf("coordinates.platform %q must match the Exposure namespace %q", in.Coordinates.Platform, in.Namespace))
	}
	if in.Installation.Profile != ProfileRegistered &&
		(in.Coordinates.Landscape != in.Installation.Landscape || in.Instance != in.Installation.Instance) {
		return exposureRefusedAccepted(boron.ReasonCoordinatesMismatch,
			"declared landscape/instance must match the trusted Garden profile metadata")
	}

	path := boron.NormalizePath(in.Path)
	if !boron.ValidPath(path) {
		return exposureRefusedAccepted(boron.ReasonUnsupportedMatch,
			fmt.Sprintf("path %q is not a segment-boundary prefix match", path))
	}

	hostname := boron.Hostname(in.Coordinates, in.Instance, in.TunnelZone)

	if !in.TLSChecked || !in.TLSCovered {
		message := in.TLSMessage
		if message == "" {
			message = fmt.Sprintf("zone %q cannot prove exact DNS/edge-TLS coverage for %q", in.TunnelZone, hostname)
		}
		d := exposureRefusedAccepted(boron.ReasonUnsupportedTLSCoverage, message)
		d.Hostname = hostname
		return d
	}

	accepted := Condition{Type: TypeAccepted, Status: StatusTrue, Reason: boron.ReasonAccepted, Message: "exposure admitted"}

	if !in.BackendFound || !in.BackendPortFound {
		message := "backend Service not found"
		if in.BackendFound {
			message = "backend Service does not expose the named port"
		}
		return exposureRefusedResolved(accepted, hostname, boron.ReasonBackendNotFound, message)
	}
	if !boron.SharedBackendAllowed(in.BackendPublic, in.AllowSharedBackend) {
		return exposureRefusedResolved(accepted, hostname, boron.ReasonSharedBackendDenied,
			"backend Service is publicly routed; set allowSharedBackend: true to acknowledge the public path bypasses Access")
	}

	policyIDs := make([]string, 0, len(in.PolicyNames))
	var missing []string
	for _, name := range in.PolicyNames {
		id, ok := in.ResolvedPolicy[name]
		if !ok || id == "" {
			missing = append(missing, name)
			continue
		}
		policyIDs = append(policyIDs, id)
	}
	if len(missing) > 0 {
		return exposureRefusedResolved(accepted, hostname, boron.ReasonPolicyMissing,
			fmt.Sprintf("access policies not found: %v — nothing programmed (no policy, no route)", missing))
	}

	resolved := Condition{Type: TypeResolvedRefs, Status: StatusTrue, Reason: boron.ReasonResolvedRefs, Message: "backend and every access policy resolved"}

	if in.HasRival && !boron.Older(in.Self, in.Oldest) {
		return ExposureDecision{
			Hostname: hostname,
			Conditions: []Condition{
				accepted,
				resolved,
				{Type: TypeConflicted, Status: StatusTrue, Reason: boron.ReasonHostnameConflict,
					Message: fmt.Sprintf("hostname+path already claimed by older exposure %s/%s (oldest wins)", in.Oldest.Namespace, in.Oldest.Name)},
				{Type: TypeProgrammed, Status: StatusFalse, Reason: boron.ReasonHostnameConflict, Message: "conflicted exposure is not programmed"},
			},
			Events: []Event{{EventWarning, boron.ReasonHostnameConflict, "hostname+path conflict: oldest exposure wins"}},
		}
	}

	return ExposureDecision{
		Hostname: hostname,
		Program: &ExposureProgram{
			Hostname:  hostname,
			Path:      path,
			Backend:   boron.BackendURL(in.Namespace, in.BackendName, in.BackendPort),
			PolicyIDs: policyIDs,
		},
		Conditions: []Condition{
			accepted,
			resolved,
			{Type: TypeConflicted, Status: StatusFalse, Reason: boron.ReasonNoConflict, Message: "no hostname conflict"},
		},
	}
}

// ProgrammedCondition is the condition the controller flips after the provider
// writes succeed (or fail). It is exported because the write outcome surfaces in
// the controller's I/O path, not in DecideExposure.
func ProgrammedCondition(ok bool, message string) Condition {
	if ok {
		return Condition{Type: TypeProgrammed, Status: StatusTrue, Reason: boron.ReasonProgrammed, Message: "dns, access application, and tunnel ingress rule are live"}
	}
	return Condition{Type: TypeProgrammed, Status: StatusFalse, Reason: boron.ReasonProgrammingPending, Message: message}
}

func exposureRefusedAccepted(reason, message string) ExposureDecision {
	return ExposureDecision{
		Conditions: []Condition{
			{Type: TypeAccepted, Status: StatusFalse, Reason: reason, Message: message},
			{Type: TypeProgrammed, Status: StatusFalse, Reason: reason, Message: "nothing programmed"},
		},
		Events: []Event{{EventWarning, reason, message}},
	}
}

func exposureRefusedResolved(accepted Condition, hostname, reason, message string) ExposureDecision {
	return ExposureDecision{
		Hostname: hostname,
		Conditions: []Condition{
			accepted,
			{Type: TypeResolvedRefs, Status: StatusFalse, Reason: reason, Message: message},
			{Type: TypeProgrammed, Status: StatusFalse, Reason: reason, Message: "nothing programmed"},
		},
		Events: []Event{{EventWarning, reason, message}},
	}
}
