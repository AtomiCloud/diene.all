package authengine

import (
	"maps"
	"strings"
	"time"
)

// Registered OIDC and AtomiCloud claim names the engine reads. They are named
// constants rather than inline strings because the same key is read by the
// validator, the principal mapper, and the onboarding machinery, and a typo in
// any one of them silently degrades to "claim absent".
const (
	// ClaimSubject is the OIDC `sub` claim: the stable IdP user id. It is the
	// only source of caller identity the ownership guard trusts.
	ClaimSubject = "sub"
	// ClaimIssuer is the OIDC `iss` claim.
	ClaimIssuer = "iss"
	// ClaimAudience is the OIDC `aud` claim.
	ClaimAudience = "aud"
	// ClaimExpiry is the OIDC `exp` claim.
	ClaimExpiry = "exp"
	// ClaimUsername is the Logto `username` claim.
	ClaimUsername = "username"
	// ClaimEmail is the OIDC `email` claim.
	ClaimEmail = "email"
	// ClaimEmailVerified is the OIDC `email_verified` claim.
	ClaimEmailVerified = "email_verified"
	// ClaimRoles is the coarse role claim the ownership guard's role half reads.
	ClaimRoles = "roles"
	// ClaimScope is the OAuth `scope` claim, a space-delimited list.
	ClaimScope = "scope"
	// ClaimHomeLandscape is the per-client-session routing claim deciding which
	// landscape a caller's home traffic goes to. It is emitted onto tokens by an
	// IdP JWT customizer that logto-operator owns declaratively; applications
	// only ever read it.
	ClaimHomeLandscape = "home_landscape"
)

// Claims is a decoded JWT claim set.
//
// Claim values cross the wire as untyped JSON, so every accessor is total: it
// reports presence alongside the value instead of panicking or zero-valuing a
// wrong-typed claim into a silent default. That distinction matters because
// "claim absent" and "claim present but false" drive different branches of the
// onboarding machinery.
type Claims map[string]any

// Text returns the claim named name when it is present and holds a string.
func (c Claims) Text(name string) (string, bool) {
	value, found := c[name].(string)
	return value, found
}

// Flag returns the claim named name as a boolean. IdPs emit custom-data
// booleans both natively and as the strings "true"/"false" (Logto's custom_data
// round-trip does the latter), so both encodings are accepted.
func (c Claims) Flag(name string) (flag bool, present bool) {
	switch value := c[name].(type) {
	case bool:
		return value, true
	case string:
		switch value {
		case "true":
			return true, true
		case "false":
			return false, true
		default:
			return false, false
		}
	default:
		return false, false
	}
}

// List returns the claim named name as a string list. A single string value is
// returned as a one-element list; mixed lists keep only their string members.
func (c Claims) List(name string) ([]string, bool) {
	switch value := c[name].(type) {
	case []string:
		return append([]string(nil), value...), true
	case string:
		return []string{value}, true
	case []any:
		values := make([]string, 0, len(value))
		for _, member := range value {
			if text, ok := member.(string); ok {
				values = append(values, text)
			}
		}
		return values, true
	default:
		return nil, false
	}
}

// Space returns the claim named name split on whitespace, which is how OAuth
// encodes the `scope` claim. Empty members are dropped.
func (c Claims) Space(name string) ([]string, bool) {
	value, found := c.Text(name)
	if !found {
		return nil, false
	}
	return strings.Fields(value), true
}

// Instant returns the claim named name as a UTC instant, accepting the JSON
// number encodings a decoder may produce for NumericDate seconds.
func (c Claims) Instant(name string) (time.Time, bool) {
	switch value := c[name].(type) {
	case float64:
		return time.Unix(int64(value), 0).UTC(), true
	case int64:
		return time.Unix(value, 0).UTC(), true
	case int:
		return time.Unix(int64(value), 0).UTC(), true
	default:
		return time.Time{}, false
	}
}

// Clone returns a shallow copy so a mapped principal never aliases the claim
// set the validator decoded.
func (c Claims) Clone() Claims {
	if c == nil {
		return nil
	}
	clone := make(Claims, len(c))
	maps.Copy(clone, c)
	return clone
}
