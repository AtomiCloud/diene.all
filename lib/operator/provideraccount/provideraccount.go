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

// CredentialPointerPath derives the canonical S10 logical credential pointer.
// It returns a pointer only; callers must not use this pure package to read or
// hold the credential value.
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
	return "/" + platform + "/" + landscape + "/" + class + "/" + vendor + "-account-" + name, nil
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

func validateSegment(field, value string) error {
	if strings.TrimSpace(value) == "" {
		return fmt.Errorf("%s must be nonblank", field)
	}
	if strings.Contains(value, "/") {
		return fmt.Errorf("%s must be one path segment", field)
	}
	return nil
}
