// Package clone deep-clones the string-keyed configuration domain so a caller
// cannot mutate a value it handed across a public ownership boundary. Maps,
// slices, arrays, pointers, and interfaces are copied recursively; a shared or
// cyclic object is cloned once and its aliasing preserved, so alias topology
// survives the copy and self-referential structures terminate.
//
// A struct is first copied whole by value, which preserves every field —
// including unexported ones, so a time.Time keeps its private wall-clock and
// location — and then every EXPORTED mutable field is recursively deep-cloned so
// caller mutation through an exported map, slice, or pointer field cannot reach
// the clone. The one explicit boundary: a map, slice, or pointer reachable only
// through an UNEXPORTED field cannot be copied by reflection and therefore stays
// shared with the source; the supported configuration domain (JSON-like
// string-keyed maps of scalars, plus value-semantic structs such as time.Time)
// has no such fields, so this boundary is never crossed in practice.
//
// It is an internal package with an exported, black-box-testable API, not part
// of the public config surface.
package clone

import "reflect"

// Ref identifies a reference-typed source object by pointer and type, so the
// clone memo can recognise a repeated or cyclic object across recursion. For a
// slice the length and capacity are also part of the identity: two views over
// one backing array that share a first element (equal pointer and type) but
// differ in length or capacity are distinct headers and must clone separately,
// so a subslice never resolves to the wrong header. Maps and pointers leave Len
// and Cap zero, as their address alone is a unique identity.
type Ref struct {
	// Pointer is the underlying object address (map, slice, or pointer).
	Pointer uintptr
	// Type is the source type, disambiguating an address reused across types.
	Type reflect.Type
	// Len and Cap complete a slice header's identity; zero for maps and pointers.
	Len, Cap int
}

// Memo records, for each already-cloned reference-typed source object, the clone
// produced for it. Threading a Memo through [Reflect] preserves shared aliases
// (the same source object clones to the same destination object) and terminates
// on cycles. Create one per top-level clone with [NewMemo].
type Memo map[Ref]reflect.Value

// NewMemo returns an empty memo for a single top-level clone operation.
func NewMemo() Memo { return Memo{} }

// Map returns a deep clone of a string-keyed map, cloning each value with
// [Reflect] under a fresh [Memo] so shared and cyclic values inside the map are
// preserved. A nil map clones to nil.
func Map(source map[string]any) map[string]any {
	if source == nil {
		return nil
	}
	// Value clones the whole map under one Memo, so aliases repeated across keys
	// stay shared. Cloning a map[string]any always yields a map[string]any; a
	// failed assertion would be a clone invariant break, so force it (and panic)
	// rather than silently discard the tree.
	//nolint:forcetypeassert,revive // guaranteed by the input type; must not fail silently.
	return Value(source).(map[string]any)
}

// Value returns a deep clone of value under a fresh [Memo], preserving its
// concrete type, shared aliases, and cycles across the whole value. A nil value
// clones to nil.
func Value(value any) any {
	if value == nil {
		return nil
	}
	return Reflect(reflect.ValueOf(value), NewMemo()).Interface()
}

// Reflect is the recursive core of [Value] and [Map]. It is exported so the
// clone logic has an external black-box test surface, per the zero-private-logic
// rule. memo maps each visited reference-typed source object to its clone, so a
// repeated object clones once (alias topology preserved) and a cyclic object
// terminates. The destination is registered in memo before its children are
// cloned, which is what makes a self-referential map or pointer safe.
func Reflect(source reflect.Value, memo Memo) reflect.Value {
	//nolint:exhaustive // the default case copies every remaining (leaf) kind by value.
	switch source.Kind() {
	case reflect.Interface:
		if source.IsNil() {
			return source
		}
		out := reflect.New(source.Type()).Elem()
		out.Set(Reflect(source.Elem(), memo))
		return out
	case reflect.Pointer:
		if source.IsNil() {
			return source
		}
		ref := Ref{Pointer: source.Pointer(), Type: source.Type()}
		if existing, ok := memo[ref]; ok {
			return existing
		}
		out := reflect.New(source.Type().Elem())
		memo[ref] = out
		out.Elem().Set(Reflect(source.Elem(), memo))
		return out
	case reflect.Map:
		if source.IsNil() {
			return source
		}
		ref := Ref{Pointer: source.Pointer(), Type: source.Type()}
		if existing, ok := memo[ref]; ok {
			return existing
		}
		out := reflect.MakeMapWithSize(source.Type(), source.Len())
		memo[ref] = out
		iterator := source.MapRange()
		for iterator.Next() {
			out.SetMapIndex(Reflect(iterator.Key(), memo), Reflect(iterator.Value(), memo))
		}
		return out
	case reflect.Slice:
		if source.IsNil() {
			return source
		}
		ref := Ref{Pointer: source.Pointer(), Type: source.Type(), Len: source.Len(), Cap: source.Cap()}
		if existing, ok := memo[ref]; ok {
			return existing
		}
		out := reflect.MakeSlice(source.Type(), source.Len(), source.Len())
		memo[ref] = out
		for index := range source.Len() {
			out.Index(index).Set(Reflect(source.Index(index), memo))
		}
		return out
	case reflect.Array:
		out := reflect.New(source.Type()).Elem()
		for index := range source.Len() {
			out.Index(index).Set(Reflect(source.Index(index), memo))
		}
		return out
	case reflect.Struct:
		// Copy the whole struct first so unexported invariants (e.g. time.Time's
		// private wall-clock and location) survive, then deep-clone each exported
		// mutable field so caller mutation through it cannot reach the clone.
		// Unexported reference fields are left as the whole-value copy shares them;
		// the supported domain has none (see the package doc).
		out := reflect.New(source.Type()).Elem()
		out.Set(source)
		for index := range source.NumField() {
			if field := out.Field(index); field.CanSet() {
				field.Set(Reflect(source.Field(index), memo))
			}
		}
		return out
	default:
		// Scalars are immutable; the source value is copied whole by .Interface()/Set.
		return source
	}
}
