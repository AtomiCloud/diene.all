/// Narrowing and deterministic projection of JSON-like records.
library;

import 'package:diene_result/diene_result.dart';

import 'merge.dart';
import 'util_problem.dart';

/// Narrows [value] to a plain JSON object: a `Map` keyed by `String` that is
/// not a list.
///
/// This is the Dart twin of the sibling `isRecord` guard. Dart's type system
/// already separates maps from lists, so the check is a single `is` test rather
/// than the runtime null/array probing the TypeScript sibling needs.
bool isJsonObject(Object? value) => value is Map<String, Object?>;

/// Produces a deterministic clone of a config-like value.
///
/// Object keys are re-emitted in sorted order at every depth while list element
/// order is preserved and scalars pass through untouched, so two structurally
/// equal configurations always project to byte-identical JSON. That makes the
/// projection safe to hash, diff, or use as a cache key.
///
/// Cyclic input cannot be projected and is reported as an `unprojectable`
/// [Problem] rather than recursing forever. A value merely *shared* across
/// sibling branches (a non-cyclic DAG) is fine and is emitted at each position.
Result<Object?> stableConfig(Object? value) {
  try {
    return Ok<Object?>(_project(value, <Object>[], '<root>'));
  } on _CycleDetected catch (cycle) {
    return utilFailure<Object?>(
      util: UtilName.record,
      code: UtilErrorCode.unprojectable,
      operation: 'stableConfig',
      message: 'value contains a circular reference',
      details: <String, Object?>{'path': cycle.path},
    );
  }
}

/// Thrown internally by [_project] and converted to a [Problem] by
/// [stableConfig]; never visible to callers.
final class _CycleDetected implements Exception {
  const _CycleDetected(this.path);

  final String path;
}

Object? _project(Object? value, List<Object> ancestors, String path) {
  if (value is Map<String, Object?>) {
    _guardCycle(value, ancestors, path);
    final List<String> keys = value.keys.toList()..sort();
    final List<Object> nested = <Object>[...ancestors, value];
    return <String, Object?>{
      for (final String key in keys)
        key: _project(value[key], nested, '$path.$key'),
    };
  }
  if (value is List<Object?>) {
    _guardCycle(value, ancestors, path);
    final List<Object> nested = <Object>[...ancestors, value];
    return <Object?>[
      for (int index = 0; index < value.length; index += 1)
        _project(value[index], nested, '$path[$index]'),
    ];
  }
  return value;
}

void _guardCycle(Object node, List<Object> ancestors, String path) {
  for (final Object ancestor in ancestors) {
    if (identical(ancestor, node)) {
      throw _CycleDetected(path);
    }
  }
}

/// Deterministically projects a configuration object, preserving the
/// [JsonObject] type for callers that merged it with [deepMerge].
Result<JsonObject> stableConfigObject(JsonObject value) =>
    stableConfig(value).map((Object? projected) => projected! as JsonObject);
