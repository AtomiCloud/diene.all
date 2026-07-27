// Package conditions holds the shared, Kubernetes-free condition vocabulary for
// every fleet-operator controller. It defines the full set of condition types the
// verified plan and gap audit enumerate, a stable reason/message-carrying
// Condition record, and a per-module isolation contract so one module's condition
// never mutates another's. Controller adapters translate a Condition into a
// metav1.Condition on the CR status; this package imports no k8s.io/* or
// sigs.k8s.io/* package (the architecture gate enforces that).
package conditions

// Status is a condition status value. It mirrors metav1.ConditionStatus without
// importing Kubernetes; adapters convert it at the boundary.
const (
	StatusTrue    = "True"
	StatusFalse   = "False"
	StatusUnknown = "Unknown"
)

// Condition is a pure, k8s-free condition intent. Module is empty for a
// controller-level condition and set for a per-module condition so a map-shaped
// status keeps per-module isolation.
type Condition struct {
	Type    string
	Status  string
	Reason  string
	Message string
	Module  string
}

// Condition type vocabulary. The first block preserves the legacy generic set
// (kept for the inherited sample controllers and their tests); the remaining
// blocks add every condition the verified plan and gap audit enumerate across the
// six implemented controllers.
const (
	// Generic lifecycle set (legacy — preserved verbatim).
	TypeReady              = "Ready"
	TypeDrifted            = "Drifted"
	TypeConflict           = "Conflict"
	TypeWaitingForEndpoint = "WaitingForEndpoint"
	TypeBlastBrakeTripped  = "BlastBrakeTripped"

	// Dependency realization set.
	TypeProvisioned     = "Provisioned"
	TypeSecretWritten   = "SecretWritten"
	TypeUnresolved      = "Unresolved"
	TypeNotInEnvelope   = "NotInEnvelope"
	TypeSecretRetained  = "SecretRetained"
	TypeDeclarerChanged = "DeclarerChanged"
	TypeForkUnsupported = "ForkUnsupported"
	TypeQuotaExhausted  = "QuotaExhausted"

	// Platform set.
	TypeInfisicalProvisioned = "InfisicalProvisioned"
	TypeSoSRegistered        = "SoSRegistered"
	TypePipelineRendered     = "PipelineRendered"
	TypeOrphanedSource       = "OrphanedSource"

	// Webhook set.
	TypeConfigCompiled    = "ConfigCompiled"
	TypeSecretsFanned     = "SecretsFanned"
	TypeHomeChangeBlocked = "HomeChangeBlocked"
	TypeTargetNotServed   = "TargetNotServed"
	TypeAccepted          = "Accepted"
	TypeUnknownProvider   = "UnknownProvider"
	TypeOrphanedProvider  = "OrphanedProvider"
	TypeTenantProvisioned = "TenantProvisioned"

	// Decommission / deletion flow set.
	TypeRefsClear        = "RefsClear"
	TypeSnapshotted      = "Snapshotted"
	TypeExternalsDeleted = "ExternalsDeleted"
	TypeLedgerPurged     = "LedgerPurged"
	TypeTargetDeleted    = "TargetDeleted"

	// Traffic set.
	TypeRecordPublished = "RecordPublished"
	TypeNoActiveServers = "NoActiveServers"

	// Cloudflare-deploy (per-version-intent) set.
	TypeVersionFound       = "VersionFound"
	TypeRolloutProgressing = "RolloutProgressing"
	TypeRolloutComplete    = "RolloutComplete"
	TypeDriftDetected      = "DriftDetected"
	TypeFailed             = "Failed"

	// Problem / edge-docs publish set.
	TypePublished     = "Published"
	TypeSchemaInvalid = "SchemaInvalid"
	TypeStale         = "Stale"
)

// New builds a Condition. It is the single derivation primitive so reason and
// message text stays stable across callers.
func New(typ, status, reason, message string) Condition {
	return Condition{Type: typ, Status: status, Reason: reason, Message: message}
}

// True builds a Condition with StatusTrue.
func True(typ, reason, message string) Condition {
	return New(typ, StatusTrue, reason, message)
}

// False builds a Condition with StatusFalse.
func False(typ, reason, message string) Condition {
	return New(typ, StatusFalse, reason, message)
}

// Unknown builds a Condition with StatusUnknown.
func Unknown(typ, reason, message string) Condition {
	return New(typ, StatusUnknown, reason, message)
}

// WithModule returns a copy of the condition scoped to a module.
func (c Condition) WithModule(module string) Condition {
	c.Module = module
	return c
}

// Upsert replaces the same-Type condition in list (matched within the condition's
// module) or appends it, returning the updated list. It never mutates the input
// slice's backing array beyond the replaced element, so callers can treat it as a
// pure transform of the condition set.
func Upsert(list []Condition, c Condition) []Condition {
	for i := range list {
		if list[i].Type == c.Type && list[i].Module == c.Module {
			out := make([]Condition, len(list))
			copy(out, list)
			out[i] = c
			return out
		}
	}
	return append(append([]Condition(nil), list...), c)
}

// ModuleSet accumulates conditions per module with per-module isolation: setting a
// condition on one module never reads or mutates another module's conditions, and
// within a module a repeated Type is replaced (not duplicated). This is the pure
// core of a map-shaped CR status.
type ModuleSet struct {
	order    []string
	byModule map[string][]Condition
}

// NewModuleSet constructs an empty ModuleSet.
func NewModuleSet() *ModuleSet {
	return &ModuleSet{byModule: map[string][]Condition{}}
}

// Set records condition c for module, replacing a same-Type condition already held
// for that module. First contact with a module preserves insertion order.
func (s *ModuleSet) Set(module string, c Condition) {
	c.Module = module
	if _, seen := s.byModule[module]; !seen {
		s.order = append(s.order, module)
	}
	s.byModule[module] = Upsert(s.byModule[module], c)
}

// For returns the conditions recorded for module, or nil if the module is absent.
func (s *ModuleSet) For(module string) []Condition {
	return s.byModule[module]
}

// Modules returns the modules that carry at least one condition, in insertion
// order.
func (s *ModuleSet) Modules() []string {
	return s.order
}
