// Package nilguard reports whether an interface value is nil or a typed nil (an
// interface wrapping a nil pointer, map, slice, func, or channel), so a public
// API can reject a missing dependency with a deterministic error instead of
// panicking on it. It is an internal package with an exported,
// black-box-testable API.
package nilguard

import "reflect"

// IsNil reports whether value is an untyped nil or a typed nil.
func IsNil(value any) bool {
	if value == nil {
		return true
	}
	reflected := reflect.ValueOf(value)
	//nolint:exhaustive // only nilable kinds can be nil; all others are never nil.
	switch reflected.Kind() {
	case reflect.Pointer, reflect.Map, reflect.Slice, reflect.Func, reflect.Chan, reflect.Interface:
		return reflected.IsNil()
	default:
		return false
	}
}
