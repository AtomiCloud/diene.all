// Package clone deep-clones configuration values, preserving concrete container,
// pointer, array, and struct types so a caller cannot mutate a value it handed
// across a public ownership boundary. It is an internal package with an
// exported, black-box-testable API, not part of the public config surface.
package clone

import "reflect"

// Map returns a deep clone of a string-keyed map, cloning each value with
// [Value]. A nil map clones to nil.
func Map(source map[string]any) map[string]any {
	if source == nil {
		return nil
	}
	out := make(map[string]any, len(source))
	for key, value := range source {
		out[key] = Value(value)
	}
	return out
}

// Value returns a deep clone of value, preserving its concrete type. Maps,
// slices, arrays, pointers, interfaces, and structs (exported fields) are copied
// recursively; scalars and other immutable kinds are returned as-is.
func Value(value any) any {
	if value == nil {
		return nil
	}
	return Reflect(reflect.ValueOf(value)).Interface()
}

// Reflect is the recursive core of [Value]. It is exported so the clone logic
// has an external black-box test surface, per the zero-private-logic rule.
func Reflect(source reflect.Value) reflect.Value {
	//nolint:exhaustive // the default case copies every remaining (immutable) kind.
	switch source.Kind() {
	case reflect.Pointer:
		if source.IsNil() {
			return source
		}
		out := reflect.New(source.Type().Elem())
		out.Elem().Set(Reflect(source.Elem()))
		return out
	case reflect.Interface:
		if source.IsNil() {
			return source
		}
		return Reflect(source.Elem())
	case reflect.Map:
		if source.IsNil() {
			return source
		}
		out := reflect.MakeMapWithSize(source.Type(), source.Len())
		iterator := source.MapRange()
		for iterator.Next() {
			out.SetMapIndex(Reflect(iterator.Key()), Reflect(iterator.Value()))
		}
		return out
	case reflect.Slice:
		if source.IsNil() {
			return source
		}
		out := reflect.MakeSlice(source.Type(), source.Len(), source.Len())
		for index := range source.Len() {
			out.Index(index).Set(Reflect(source.Index(index)))
		}
		return out
	case reflect.Array:
		out := reflect.New(source.Type()).Elem()
		for index := range source.Len() {
			out.Index(index).Set(Reflect(source.Index(index)))
		}
		return out
	case reflect.Struct:
		out := reflect.New(source.Type()).Elem()
		for index := range source.NumField() {
			if out.Field(index).CanSet() {
				out.Field(index).Set(Reflect(source.Field(index)))
			}
		}
		return out
	default:
		return source
	}
}
