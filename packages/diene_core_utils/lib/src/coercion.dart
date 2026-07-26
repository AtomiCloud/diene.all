/// C0 §3 environment-to-configuration coercion.
library;

import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';

import 'merge.dart';
import 'util_problem.dart';

const int _maxSafeInteger = 9007199254740991;
final RegExp _integer = RegExp(r'^[+-]?(?:0|[1-9]\d*)$');
final RegExp _decimal = RegExp(
  r'^[+-]?(?:(?:0|[1-9]\d*)\.\d+|(?:0|[1-9]\d*)[eE][+-]?\d+|(?:0|[1-9]\d*)\.\d+[eE][+-]?\d+)$',
);
final RegExp _index = RegExp(r'^(?:0|[1-9]\d*)$');

/// The C0 §3 path separator inside an environment or `--dart-define` key.
const String environmentPathSeparator = '__';

/// Coerces an environment scalar using the C0 §3 configuration conventions.
///
/// A blank value means UNSET and becomes `null`. `true`/`false` (any case)
/// become booleans. Safe integers and decimal forms become their Dart scalar
/// equivalents. Everything else stays a `String`. This is total: no input is
/// rejected, because C0 §3 gives every string a defined reading.
///
/// This is a CONFIGURATION-value coercion, NOT a money or wire-decimal codec.
/// Decimal forms are parsed to `double` for ergonomic config numerics (ratios,
/// timeouts, thresholds) and are therefore lossy for exact decimals. Per C0 §1,
/// money and other exact-decimal wire values travel as decimal STRINGS and must
/// not be routed through this helper; they stay strings end to end. Integers
/// beyond the IEEE-754 safe range are likewise preserved as strings, precisely
/// because coercing them would silently lose precision on web builds.
Object? coerceEnvironmentScalar(String value) {
  if (value.isEmpty) {
    return null;
  }

  final String normalized = value.toLowerCase();
  if (normalized == 'true') {
    return true;
  }
  if (normalized == 'false') {
    return false;
  }
  if (_integer.hasMatch(value)) {
    final int parsed = int.parse(value);
    return parsed.abs() <= _maxSafeInteger ? parsed : value;
  }
  if (_decimal.hasMatch(value)) {
    return double.parse(value);
  }
  return value;
}

/// Converts the [prefix]-scoped entries of [environment] into a nested
/// configuration object.
///
/// [prefix] is matched case-INSENSITIVELY (C0 §3), so `ACME_`, `acme_`, and
/// `AcMe_` all select the same entries and a host that folds its environment to
/// one case still contributes its values.
///
/// [environmentPathSeparator] separates path components and an all-digit
/// component produces a list index, so `ACME_APP__TAGS__0` and
/// `ACME_APP__TAGS__1` build `{app: {tags: [..., ...]}}`. Component names are
/// lowercased so the result merges through [deepMerge] against any YAML
/// spelling. Blank values are UNSET and are omitted entirely rather than
/// written as `null`, so a blank define cannot erase a base-layer value.
///
/// Per C0 §3 no JSON string and no comma-separated string is ever decoded: lists
/// come only from indexed keys. Such a value is simply carried through as the
/// string it is.
///
/// Every rejection is returned as a [Problem], never thrown:
///
/// - a key whose suffix is empty or has an empty path component
///   (`invalid_input`),
/// - two keys that normalise onto the same path (`conflict`),
/// - a key that treats a scalar path as a parent (`conflict`),
/// - a level that mixes indexed and named children (`invalid_input`),
/// - a list whose indexes are sparse or do not start at zero
///   (`invalid_input`).
Result<JsonObject> environmentToNestedMap(
  Map<String, String> environment, {
  required String prefix,
}) {
  final JsonObject root = <String, Object?>{};
  // C0 §3 case-insensitive key matching covers the PREFIX as well as the path:
  // `acme_app__name` and `ACME_APP__NAME` name the same setting, so a host that
  // lowercases its environment must not silently contribute nothing.
  final String foldedPrefix = prefix.toLowerCase();
  final List<MapEntry<String, String>> entries =
      environment.entries
          .where(
            (MapEntry<String, String> entry) =>
                entry.key.toLowerCase().startsWith(foldedPrefix),
          )
          .toList()
        ..sort(
          (MapEntry<String, String> left, MapEntry<String, String> right) =>
              left.key.toLowerCase().compareTo(right.key.toLowerCase()),
        );

  for (final MapEntry<String, String> entry in entries) {
    if (entry.value.isEmpty) {
      continue;
    }
    final String suffix = entry.key.substring(prefix.length);
    final List<String> path = suffix.split(environmentPathSeparator);
    if (suffix.isEmpty || path.any((String segment) => segment.isEmpty)) {
      return invalidUtilInput<JsonObject>(
        util: UtilName.coercion,
        operation: 'environmentToNestedMap',
        field: entry.key,
        message:
            'key must carry non-empty $environmentPathSeparator-separated path '
            'components after the prefix',
      );
    }
    final Result<void> inserted = _insertPath(
      root,
      path,
      coerceEnvironmentScalar(entry.value),
      entry.key,
    );
    if (inserted case Err<void>(problem: final Problem problem)) {
      return Err<JsonObject>(problem);
    }
  }

  return _materializeCollections(
    root,
    '<root>',
  ).map((Object? value) => value! as JsonObject);
}

Result<void> _insertPath(
  JsonObject root,
  List<String> path,
  Object? value,
  String sourceKey,
) {
  JsonObject cursor = root;
  for (int index = 0; index < path.length; index += 1) {
    final String segment = path[index].toLowerCase();
    if (index == path.length - 1) {
      if (cursor.containsKey(segment)) {
        return utilFailure<void>(
          util: UtilName.coercion,
          code: UtilErrorCode.conflict,
          operation: 'environmentToNestedMap',
          message: 'key duplicates a normalised configuration path',
          details: <String, Object?>{'field': sourceKey, 'path': segment},
        );
      }
      cursor[segment] = value;
      continue;
    }

    final Object? child = cursor[segment];
    if (child == null) {
      final JsonObject created = <String, Object?>{};
      cursor[segment] = created;
      cursor = created;
    } else if (child is JsonObject) {
      cursor = child;
    } else {
      return utilFailure<void>(
        util: UtilName.coercion,
        code: UtilErrorCode.conflict,
        operation: 'environmentToNestedMap',
        message: 'key treats a scalar configuration path as a parent',
        details: <String, Object?>{'field': sourceKey, 'path': segment},
      );
    }
  }
  return const Ok<void>(null);
}

Result<Object?> _materializeCollections(Object? value, String path) {
  if (value is! JsonObject) {
    return Ok<Object?>(deepClone(value));
  }

  final bool hasIndexKey = value.keys.any(_isIndex);
  if (hasIndexKey && !value.keys.every(_isIndex)) {
    return invalidUtilInput<Object?>(
      util: UtilName.coercion,
      operation: 'environmentToNestedMap',
      field: path,
      message: 'path mixes indexed and named child keys',
    );
  }

  if (hasIndexKey) {
    final List<int> indexes = value.keys.map(int.parse).toList()..sort();
    for (int expected = 0; expected < indexes.length; expected += 1) {
      if (indexes[expected] != expected) {
        return invalidUtilInput<Object?>(
          util: UtilName.coercion,
          operation: 'environmentToNestedMap',
          field: path,
          message: 'list uses sparse indexes; expected $expected',
        );
      }
    }
    final List<Object?> items = <Object?>[];
    for (final int index in indexes) {
      final Result<Object?> item = _materializeCollections(
        value['$index'],
        '$path$environmentPathSeparator$index',
      );
      switch (item) {
        case Ok<Object?>(value: final Object? materialized):
          items.add(materialized);
        case Err<Object?>(problem: final Problem problem):
          return Err<Object?>(problem);
      }
    }
    return Ok<Object?>(items);
  }

  final JsonObject materialized = <String, Object?>{};
  for (final MapEntry<String, Object?> entry in value.entries) {
    final Result<Object?> child = _materializeCollections(
      entry.value,
      '$path$environmentPathSeparator${entry.key}',
    );
    switch (child) {
      case Ok<Object?>(value: final Object? projected):
        materialized[entry.key] = projected;
      case Err<Object?>(problem: final Problem problem):
        return Err<Object?>(problem);
    }
  }
  return Ok<Object?>(materialized);
}

bool _isIndex(String value) => _index.hasMatch(value);
