// Package provideraccount resolves explicit dependency-module account selectors
// against the ProviderAccount registry rendered by carbon. It is deliberately a
// pure domain package: it reads no Kubernetes objects, calls no provider, and
// holds credential pointers only, never credential values.
package provideraccount

import (
	"errors"
	"fmt"
	"strings"
)

// Stable error categories. Resolution failures are strict refusals: callers
// must surface an Unresolved condition rather than choosing a default account.
var (
	ErrUnresolved                  = errors.New("provideraccount: unresolved account")
	ErrSelectorRequired            = errors.New("provideraccount: account selector is required")
	ErrInvalidSelector             = errors.New("provideraccount: invalid account selector")
	ErrAccountNotFound             = errors.New("provideraccount: selected account not found")
	ErrAmbiguousAccount            = errors.New("provideraccount: ambiguous account selection")
	ErrInvalidRegistry             = errors.New("provideraccount: invalid registry")
	ErrDuplicateNameWithinVendor   = errors.New("provideraccount: duplicate name within vendor")
	ErrDuplicateVendorNameIdentity = errors.New("provideraccount: duplicate vendor/name identity")
	ErrInvalidCredentialPointer    = errors.New("provideraccount: invalid credential pointer")
)

// Account is one carbon-rendered ProviderAccount registry entry. Its identity
// is exactly the vendor/name pair; the account name is never inferred.
type Account struct {
	Vendor string
	Name   string
}

// ModuleAccountSelector is the explicit account selection attached to a module.
// Vendor comes from the module's selected dependency type and Name is the
// `account: {name}` selector. Both are required.
type ModuleAccountSelector struct {
	Vendor string
	Name   string
}

// OnboardingCheck is the pure result shape reserved for Phase 3 account
// onboarding and quota adapters. This package deliberately performs none of
// those checks.
type OnboardingCheck struct {
	Account        Account
	Ready          bool
	QuotaAvailable bool
	Reason         string
}

// Resolve finds the one account explicitly named by module. It never defaults
// or infers an account: an absent selector, a missing match, and multiple
// matches are all typed strict-refusal errors.
func Resolve(module ModuleAccountSelector, accounts []Account) (Account, error) {
	if strings.TrimSpace(module.Name) == "" {
		return Account{}, &ResolutionError{
			Kind:   ResolutionSelectorRequired,
			Vendor: module.Vendor,
			Name:   module.Name,
			Reason: "name is required; account selection must be explicit",
		}
	}
	if err := validateSegment("selector.vendor", module.Vendor); err != nil {
		return Account{}, &ResolutionError{
			Kind:   ResolutionInvalidSelector,
			Vendor: module.Vendor,
			Name:   module.Name,
			Reason: err.Error(),
		}
	}
	if err := validateSegment("selector.name", module.Name); err != nil {
		return Account{}, &ResolutionError{
			Kind:   ResolutionInvalidSelector,
			Vendor: module.Vendor,
			Name:   module.Name,
			Reason: err.Error(),
		}
	}

	var match Account
	matches := 0
	for _, account := range accounts {
		if account.Vendor == module.Vendor && account.Name == module.Name {
			match = account
			matches++
		}
	}
	switch matches {
	case 0:
		return Account{}, &ResolutionError{
			Kind: ResolutionNotFound, Vendor: module.Vendor, Name: module.Name,
			Reason: "no carbon-rendered ProviderAccount matches the explicit selector",
		}
	case 1:
		return match, nil
	default:
		return Account{}, &ResolutionError{
			Kind: ResolutionAmbiguous, Vendor: module.Vendor, Name: module.Name,
			Reason: "multiple carbon-rendered ProviderAccounts match the explicit selector",
		}
	}
}

// ResolutionKind identifies why explicit account resolution refused to proceed.
type ResolutionKind string

// Resolution refusal kinds.
const (
	ResolutionSelectorRequired ResolutionKind = "selector-required"
	ResolutionInvalidSelector  ResolutionKind = "invalid-selector"
	ResolutionNotFound         ResolutionKind = "not-found"
	ResolutionAmbiguous        ResolutionKind = "ambiguous"
)

// ResolutionError retains the module selector and strict-refusal reason.
type ResolutionError struct {
	Kind   ResolutionKind
	Vendor string
	Name   string
	Reason string
}

// Error implements error.
func (e *ResolutionError) Error() string {
	return fmt.Sprintf("%s: %s for vendor %q account %q", ErrUnresolved, e.Reason, e.Vendor, e.Name)
}

// Is makes both the general strict-refusal category and its concrete reason
// available to errors.Is callers.
func (e *ResolutionError) Is(target error) bool {
	if target == ErrUnresolved {
		return true
	}
	switch e.Kind {
	case ResolutionSelectorRequired:
		return target == ErrSelectorRequired
	case ResolutionInvalidSelector:
		return target == ErrInvalidSelector
	case ResolutionNotFound:
		return target == ErrAccountNotFound
	case ResolutionAmbiguous:
		return target == ErrAmbiguousAccount
	default:
		return false
	}
}

// ValidateRegistry enforces the registry identity law before a controller
// consumes a watch result: account names are unique within a vendor, and the
// fleet has at most one entry for each vendor/name identity.
func ValidateRegistry(accounts []Account) error {
	seen := make(map[string]struct{}, len(accounts))
	for _, account := range accounts {
		if err := validateAccount(account); err != nil {
			return &RegistryError{Vendor: account.Vendor, Name: account.Name, Reason: err.Error()}
		}
		identity := account.Vendor + "\x00" + account.Name
		if _, exists := seen[identity]; exists {
			return &RegistryError{
				Vendor: account.Vendor,
				Name:   account.Name,
				Reason: "name must be unique within a vendor and vendor/name identity must be fleet-wide unique",
			}
		}
		seen[identity] = struct{}{}
	}
	return nil
}

// RegistryError describes an invalid ProviderAccount registry entry.
type RegistryError struct {
	Vendor string
	Name   string
	Reason string
}

// Error implements error.
func (e *RegistryError) Error() string {
	return fmt.Sprintf("%s: vendor %q account %q %s", ErrInvalidRegistry, e.Vendor, e.Name, e.Reason)
}

// Is exposes the general invalid-registry category and both formulations of the
// duplicate identity law.
func (e *RegistryError) Is(target error) bool {
	if target == ErrInvalidRegistry {
		return true
	}
	if e.Reason == "name must be unique within a vendor and vendor/name identity must be fleet-wide unique" {
		return target == ErrDuplicateNameWithinVendor || target == ErrDuplicateVendorNameIdentity
	}
	return false
}

// CredentialPointerPath derives the canonical S10 logical credential pointer
//
//	/{platform}/{landscape}/{class}/{vendor}-account-{name}
//
// Every input is validated against the ProviderAccount-compatible DNS-label
// grammar documented on validateSegment. The ordinary unambiguous form is
// preserved byte-for-byte; only vendor/name pairs for which the raw final
// component has multiple schema-valid decompositions use the reversible escape
// documented on credentialPointerComponent. It returns a pointer only; callers
// must not use this pure package to read or hold the credential value.
func CredentialPointerPath(platform, landscape, class, vendor, name string) (string, error) {
	segments := []struct {
		field string
		value string
	}{
		{field: "platform", value: platform},
		{field: "landscape", value: landscape},
		{field: "class", value: class},
		{field: "vendor", value: vendor},
		{field: "name", value: name},
	}
	for _, segment := range segments {
		if err := validateSegment(segment.field, segment.value); err != nil {
			return "", &CredentialPointerError{Field: segment.field, Value: segment.value, Reason: err.Error()}
		}
	}
	component := credentialPointerComponent(vendor, name)
	return "/" + platform + "/" + landscape + "/" + class + "/" + component, nil
}

// CredentialPointerError identifies the malformed segment without exposing a
// credential value.
type CredentialPointerError struct {
	Field  string
	Value  string
	Reason string
}

// Error implements error.
func (e *CredentialPointerError) Error() string {
	return fmt.Sprintf("%s: %s segment %q %s", ErrInvalidCredentialPointer, e.Field, e.Value, e.Reason)
}

// Unwrap exposes ErrInvalidCredentialPointer.
func (*CredentialPointerError) Unwrap() error { return ErrInvalidCredentialPointer }

func validateAccount(account Account) error {
	if err := validateSegment("vendor", account.Vendor); err != nil {
		return err
	}
	return validateSegment("name", account.Name)
}

const (
	maxSchemaSegmentLength           = 63
	accountPointerDelimiter          = "-account-"
	ambiguousAccountPointerPrefix    = "_pa_"
	ambiguousAccountPointerSeparator = "_"
)

// credentialPointerComponent preserves the exact S10
// {vendor}-account-{name} component whenever it has exactly one decomposition
// into two schema-valid ProviderAccount identity fields. If another valid split
// exists, it emits _pa_{vendor}_{name}. Underscore is outside the committed
// identity grammar, so escaped components cannot collide with raw components;
// it is also absent from vendor and name, so stripping the prefix and splitting
// once on underscore reverses the escaped form without normalizing either
// identity.
func credentialPointerComponent(vendor, name string) string {
	candidate := vendor + accountPointerDelimiter + name
	if hasMultipleSchemaIdentitySplits(candidate) {
		return ambiguousAccountPointerPrefix + vendor + ambiguousAccountPointerSeparator + name
	}
	return candidate
}

// hasMultipleSchemaIdentitySplits reports whether component has more than one
// -account- position whose left and right sides both belong to the committed
// ProviderAccount DNS-label domain. Counting only valid decompositions avoids
// churning byte-compatible paths merely because an invalid split happens to
// contain the delimiter text (for example, when one side would end in a hyphen
// or exceed 63 bytes).
func hasMultipleSchemaIdentitySplits(component string) bool {
	validSplits := 0
	for searchFrom := 0; ; {
		relativeStart := strings.Index(component[searchFrom:], accountPointerDelimiter)
		if relativeStart < 0 {
			return false
		}

		delimiterStart := searchFrom + relativeStart
		left := component[:delimiterStart]
		right := component[delimiterStart+len(accountPointerDelimiter):]
		if isSchemaSegment(left) && isSchemaSegment(right) {
			validSplits++
			if validSplits > 1 {
				return true
			}
		}
		searchFrom = delimiterStart + 1
	}
}

// validateSegment enforces the committed ProviderAccount vendor/name schema on
// every logical pointer component. It is deliberately reject-only: values are
// never trimmed, case-folded, escaped, or otherwise normalized. A valid value
// is a 1-63 byte lowercase DNS label: ASCII letters, digits, and internal
// hyphens, beginning and ending with a letter or digit. This rejects slash,
// backslash, dot/dot-dot, percent escapes, whitespace, Unicode, uppercase, and
// every other non-schema spelling while admitting the full schema domain,
// including labels containing "account".
func validateSegment(field, value string) error {
	if strings.TrimSpace(value) == "" {
		return fmt.Errorf("%s must be nonblank", field)
	}
	if !isSchemaSegment(value) {
		return fmt.Errorf(
			"%s must be a schema-compatible safe path segment of 1-63 lowercase ASCII letters, digits, or hyphens, starting and ending with a letter or digit; %q is not permitted",
			field, value,
		)
	}
	return nil
}

func isSchemaSegment(value string) bool {
	if len(value) == 0 || len(value) > maxSchemaSegmentLength || value[0] == '-' || value[len(value)-1] == '-' {
		return false
	}
	for index := range len(value) {
		character := value[index]
		if (character < 'a' || character > 'z') && (character < '0' || character > '9') && character != '-' {
			return false
		}
	}
	return true
}
