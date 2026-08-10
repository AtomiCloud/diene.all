package authengine

import "slices"

// PolicyKind is the quantifier a named policy applies to its target claims.
type PolicyKind string

// The two policy quantifiers. They mirror the guard's own role halves so an
// application has one vocabulary for both inline guards and named policies.
const (
	// PolicyAny passes when the caller carries at least one target value.
	PolicyAny PolicyKind = "any"
	// PolicyAll passes when the caller carries every target value.
	PolicyAll PolicyKind = "all"
)

// Policy is a named claim requirement declared in configuration.
//
// Named policies cover the endpoints that have no owner variant at all — an
// admin-only report, a system callback — where a nullable userId would be
// meaningless. Every OWNED resource still uses the guard: a policy is the
// exception, not the default.
type Policy struct {
	// Kind is the quantifier applied to Target.
	Kind PolicyKind `json:"type"`
	// Field is the claim the values are read from, e.g. "roles".
	Field string `json:"field"`
	// Target is the required claim values.
	Target []string `json:"target"`
}

// PolicySet is an application's named-policy registry, keyed by policy name.
//
// Applications declare their own role constants and policies: there is no central
// role service, and this library ships no roles of its own.
type PolicySet map[string]Policy

// Names returns the declared policy names in sorted order, so a consumer can
// enumerate what its configuration actually registered.
func (s PolicySet) Names() []string {
	names := make([]string, 0, len(s))
	for name := range s {
		names = append(names, name)
	}
	slices.Sort(names)
	return names
}

// Policy authorizes the principal against the named policy in policies.
//
// An unknown policy name is a 500-class configuration failure, never a silent
// pass: an endpoint that names a policy its configuration forgot to declare must
// fail closed and say so.
func (g Guard) Policy(principal Principal, policies PolicySet, name string) error {
	declared, found := policies[name]
	if !found {
		return g.problems.Raise(ProblemPolicyUnknown,
			"the named policy is not declared in the auth configuration",
			map[string]any{"policy": name, "declared": policies.Names()})
	}
	if g.satisfies(principal, declared) {
		return nil
	}
	data := map[string]any{
		"subject":  principal.Subject,
		"policy":   name,
		"field":    declared.Field,
		"kind":     string(declared.Kind),
		"required": declared.Target,
		"granted":  g.checker.Scope(principal, declared.Field),
	}
	g.log(data)
	return g.problems.Raise(ProblemOwnershipDenied,
		"the caller does not satisfy the named policy", data)
}

// satisfies applies a policy's quantifier. An unrecognised quantifier fails
// closed rather than defaulting to the permissive reading.
func (g Guard) satisfies(principal Principal, declared Policy) bool {
	switch declared.Kind {
	case PolicyAny:
		return g.checker.HasAny(principal, declared.Field, declared.Target)
	case PolicyAll:
		return g.checker.HasAll(principal, declared.Field, declared.Target)
	default:
		return false
	}
}
