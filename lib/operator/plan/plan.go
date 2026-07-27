// Package plan holds the pure, deterministic would-apply plan the lifecycle
// framework produces and the observe-mode runner consumes. A Plan is an ordered
// set of Actions across every target class the fleet touches (Kubernetes, vendor,
// DNS, secret, Git). Each Action records its operation, target, destructive
// character, a stable details hash, and safe pointer-only metadata — never a
// secret value. A Plan exposes exact counts, its destructive subset, equality and
// diff, emptiness, and human/condition summaries, all without side effects.
//
// This package is pure domain: it imports no k8s.io/* or sigs.k8s.io/* package.
// The condition vocabulary lives in lib/operator/conditions; the symbols re-exported
// here are a compatibility facade for the inherited sample controllers and tests.
package plan

import (
	"fmt"
	"hash/fnv"
	"maps"
	"slices"
	"strings"

	"github.com/AtomiCloud/diene.fleet-operator/lib/operator/conditions"
)

// ─── Condition-vocabulary compatibility facade ───────────────────────────────
//
// These alias the authoritative vocabulary in lib/operator/conditions so the
// inherited note/journal controllers and their tests keep compiling unchanged.

// Condition is the pure, k8s-free condition intent (aliased to conditions.Condition).
type Condition = conditions.Condition

// Standard condition status values.
const (
	StatusTrue  = conditions.StatusTrue
	StatusFalse = conditions.StatusFalse
)

// Legacy generic condition type vocabulary, preserved for existing consumers.
const (
	TypeReady              = conditions.TypeReady
	TypeDrifted            = conditions.TypeDrifted
	TypeConflict           = conditions.TypeConflict
	TypeWaitingForEndpoint = conditions.TypeWaitingForEndpoint
	TypeBlastBrakeTripped  = conditions.TypeBlastBrakeTripped
)

// ─── The deterministic action plan ───────────────────────────────────────────

// TargetKind names the class of external state an action touches.
type TargetKind string

// Target kinds the fleet operates across.
const (
	TargetKubernetes TargetKind = "kubernetes"
	TargetVendor     TargetKind = "vendor"
	TargetDNS        TargetKind = "dns"
	TargetSecret     TargetKind = "secret"
	TargetGit        TargetKind = "git"
)

// Operation is the verb an action applies to its target.
type Operation string

// Operations a plan can express.
const (
	OpCreate Operation = "create"
	OpUpdate Operation = "update"
	OpDelete Operation = "delete"
	OpAdopt  Operation = "adopt"
)

// Target identifies the thing an action operates on with a stable, pointer-only
// identity — never a secret value.
type Target struct {
	Kind TargetKind
	ID   string
}

// ReferenceKind names the class of pointer held in action metadata. Metadata is
// intentionally unable to carry an unrestricted string value: callers must build
// an immutable Reference with NewReference, and the locator must be an absolute
// logical path rather than a payload.
type ReferenceKind string

// Reference kinds metadata may point at.
const (
	ReferenceKubernetesObject ReferenceKind = "kubernetes-object"
	ReferenceVendorObject     ReferenceKind = "vendor-object"
	ReferenceDNSRecord        ReferenceKind = "dns-record"
	ReferenceSecretPath       ReferenceKind = "secret-path"
	ReferenceGitObject        ReferenceKind = "git-object"
	ReferenceLedgerEntry      ReferenceKind = "ledger-entry"
)

// Valid reports whether k is one of the supported pointer classes.
func (k ReferenceKind) Valid() bool {
	return k == ReferenceKubernetesObject || k == ReferenceVendorObject ||
		k == ReferenceDNSRecord || k == ReferenceSecretPath ||
		k == ReferenceGitObject || k == ReferenceLedgerEntry
}

// Reference is an immutable, typed pointer to external state. Its fields are
// private so raw secret material cannot be assigned to Metadata by mistake.
// Locators use an absolute logical path such as
// /namespaces/app/secrets/database/keys/password; they identify content but never
// contain that content.
type Reference struct {
	kind    ReferenceKind
	locator string
}

// NewReference validates and constructs a pointer-only metadata value. Requiring
// a typed kind plus an absolute path makes passing a raw token/password fail
// explicitly instead of silently treating it as metadata.
func NewReference(kind ReferenceKind, locator string) (Reference, error) {
	if !kind.Valid() {
		return Reference{}, fmt.Errorf("plan: invalid reference kind %q", kind)
	}
	if len(locator) < 2 || locator[0] != '/' || locator[len(locator)-1] == '/' ||
		strings.Contains(locator, "//") || strings.Contains(locator, "/../") ||
		strings.HasSuffix(locator, "/..") || strings.Contains(locator, "/./") ||
		strings.HasSuffix(locator, "/.") {
		return Reference{}, fmt.Errorf("plan: reference locator %q must be a canonical absolute logical path", locator)
	}
	for _, r := range locator[1:] {
		if !validReferenceRune(r) {
			return Reference{}, fmt.Errorf("plan: reference locator %q contains a payload character", locator)
		}
	}
	return Reference{kind: kind, locator: locator}, nil
}

func validReferenceRune(r rune) bool {
	return r == '/' || r == '-' || r == '_' || r == '.' || r == ':' || r == '@' || r == '+' ||
		(r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9')
}

// Kind returns the reference's typed pointer class.
func (r Reference) Kind() ReferenceKind {
	return r.kind
}

// Locator returns the safe logical pointer. It is an identifier/path, never the
// referenced value.
func (r Reference) Locator() string {
	return r.locator
}

// Metadata is named action context whose values are immutable, typed references.
// The map itself is caller-owned until a plan boundary; Build and Action.Clone
// deep-copy it so later caller or executor mutation cannot alter a Plan.
type Metadata map[string]Reference

// Action is one deterministic step in a Plan. Metadata is safe, pointer-only
// context; content lives behind DetailsHash so a Plan can be logged and compared
// without ever carrying a secret value.
type Action struct {
	Op          Operation
	Target      Target
	Destructive bool
	DetailsHash string
	Metadata    Metadata
}

// Clone returns an action with independently owned metadata.
func (a Action) Clone() Action {
	cloned := a
	if len(a.Metadata) == 0 {
		cloned.Metadata = nil
		return cloned
	}
	cloned.Metadata = make(Metadata, len(a.Metadata))
	maps.Copy(cloned.Metadata, a.Metadata)
	return cloned
}

// Plan is an ordered, deterministic set of would-apply actions.
type Plan struct {
	Actions []Action
}

// HashDetails returns a stable, deterministic hash of the given detail parts. It
// is the canonical way to fill Action.DetailsHash so the same content always
// yields the same hash and the plan carries a fingerprint rather than the value.
func HashDetails(parts ...string) string {
	h := fnv.New64a()
	for _, p := range parts {
		_, _ = h.Write([]byte(p))
		_, _ = h.Write([]byte{0})
	}
	return fmt.Sprintf("%016x", h.Sum64())
}

// Build returns a Plan that owns a deep copy of every action's metadata and places
// the actions in a single deterministic order. Every execution-relevant field
// participates: target kind, operation, target id, details hash, destructive flag,
// and metadata reference keys/kinds/locators. Ordering never depends on caller
// insertion order, including when actions share the old four-field sort prefix.
func Build(actions []Action) Plan {
	sorted := make([]Action, len(actions))
	for i, action := range actions {
		sorted[i] = action.Clone()
	}
	slices.SortFunc(sorted, compareAction)
	return Plan{Actions: sorted}
}

func compareAction(a, b Action) int {
	for _, fields := range [][2]string{
		{string(a.Target.Kind), string(b.Target.Kind)},
		{string(a.Op), string(b.Op)},
		{a.Target.ID, b.Target.ID},
		{a.DetailsHash, b.DetailsHash},
	} {
		if order := strings.Compare(fields[0], fields[1]); order != 0 {
			return order
		}
	}
	if a.Destructive != b.Destructive {
		if a.Destructive {
			return 1
		}
		return -1
	}
	return compareMetadata(a.Metadata, b.Metadata)
}

func compareMetadata(a, b Metadata) int {
	aKeys := sortedMetadataKeys(a)
	bKeys := sortedMetadataKeys(b)
	for i := 0; i < len(aKeys) && i < len(bKeys); i++ {
		if order := strings.Compare(aKeys[i], bKeys[i]); order != 0 {
			return order
		}
		aRef := a[aKeys[i]]
		bRef := b[bKeys[i]]
		if order := strings.Compare(string(aRef.kind), string(bRef.kind)); order != 0 {
			return order
		}
		if order := strings.Compare(aRef.locator, bRef.locator); order != 0 {
			return order
		}
	}
	switch {
	case len(aKeys) < len(bKeys):
		return -1
	case len(aKeys) > len(bKeys):
		return 1
	default:
		return 0
	}
}

func sortedMetadataKeys(metadata Metadata) []string {
	keys := make([]string, 0, len(metadata))
	for key := range metadata {
		keys = append(keys, key)
	}
	slices.Sort(keys)
	return keys
}

// Empty reports whether the plan would change nothing. A healthy fleet yields an
// empty plan — the observe-mode acceptance case.
func (p Plan) Empty() bool {
	return len(p.Actions) == 0
}

// Len returns the number of actions.
func (p Plan) Len() int {
	return len(p.Actions)
}

// Count returns how many actions apply the given operation.
func (p Plan) Count(op Operation) int {
	n := 0
	for _, a := range p.Actions {
		if a.Op == op {
			n++
		}
	}
	return n
}

// Destructive returns the subset of actions marked destructive, preserving plan
// order.
func (p Plan) Destructive() []Action {
	var out []Action
	for _, a := range p.Actions {
		if a.Destructive {
			out = append(out, a.Clone())
		}
	}
	return out
}

// DestructiveCount returns how many actions are destructive.
func (p Plan) DestructiveCount() int {
	return len(p.Destructive())
}

// Equal reports whether two plans would apply the same set of actions, regardless
// of the order they were built from.
func (p Plan) Equal(other Plan) bool {
	here := Build(p.Actions).Actions
	there := Build(other.Actions).Actions
	if len(here) != len(there) {
		return false
	}
	for i := range here {
		if compareAction(here[i], there[i]) != 0 {
			return false
		}
	}
	return true
}

// Diff compares this plan (treated as desired) against a prior plan and returns
// the actions added (present here, absent there) and removed (present there,
// absent here), each in deterministic order.
func (p Plan) Diff(prior Plan) (added, removed []Action) {
	here := Build(p.Actions).Actions
	there := Build(prior.Actions).Actions
	i, j := 0, 0
	for i < len(here) && j < len(there) {
		switch order := compareAction(here[i], there[j]); {
		case order < 0:
			added = append(added, here[i])
			i++
		case order > 0:
			removed = append(removed, there[j])
			j++
		default:
			i++
			j++
		}
	}
	added = append(added, here[i:]...)
	removed = append(removed, there[j:]...)
	return added, removed
}

// HumanSummary renders a stable one-line description of the plan for logs.
func (p Plan) HumanSummary() string {
	if p.Empty() {
		return "no changes"
	}
	return fmt.Sprintf("%d actions: %d create, %d update, %d delete, %d adopt (%d destructive)",
		p.Len(), p.Count(OpCreate), p.Count(OpUpdate), p.Count(OpDelete), p.Count(OpAdopt), p.DestructiveCount())
}

// ConditionSummary derives the observe-mode Drifted condition from the plan
// without executing anything: an empty plan is in sync, a non-empty plan reports
// the would-apply counts.
func (p Plan) ConditionSummary() conditions.Condition {
	if p.Empty() {
		return conditions.False(conditions.TypeDrifted, "InSync", "observe mode: healthy fleet, empty plan")
	}
	return conditions.True(conditions.TypeDrifted, "WouldApply",
		fmt.Sprintf("observe mode: would apply %d actions, %d destructive (no writes)", p.Len(), p.DestructiveCount()))
}
