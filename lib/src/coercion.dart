import 'merge.dart';

const int _maxSafeInteger = 9007199254740991;
final RegExp _integer = RegExp(r'^[+-]?(?:0|[1-9]\d*)$');
final RegExp _decimal = RegExp(
  r'^[+-]?(?:(?:0|[1-9]\d*)\.\d+|(?:0|[1-9]\d*)[eE][+-]?\d+|(?:0|[1-9]\d*)\.\d+[eE][+-]?\d+)$',
);

/// Reports an invalid or ambiguous environment-to-config mapping.
final class EnvironmentCoercionException implements Exception {
  const EnvironmentCoercionException({required this.key, required this.reason});

  final String key;
  final String reason;

  @override
  String toString() => 'EnvironmentCoercionException: $key $reason';
}

/// Coerces an environment scalar using the C0 config conventions.
///
/// Blank values become `null` (unset). Booleans, safe integers, and decimal
/// numbers become their Dart scalar equivalents. Integers outside the
/// IEEE-754 safe range remain strings so web builds do not lose precision.
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

/// Converts prefixed environment entries into a nested configuration object.
///
/// `__` separates path components and numeric components produce indexed
/// lists. Blank values are omitted. JSON strings and comma-separated lists are
/// intentionally not decoded.
JsonObject environmentToNestedMap(
  Map<String, String> environment, {
  required String prefix,
}) {
  final JsonObject root = <String, Object?>{};
  final List<MapEntry<String, String>> entries = environment.entries
      .where((MapEntry<String, String> entry) => entry.key.startsWith(prefix))
      .toList()
    ..sort(
      (MapEntry<String, String> left, MapEntry<String, String> right) =>
          left.key.compareTo(right.key),
    );

  for (final MapEntry<String, String> entry in entries) {
    if (entry.value.isEmpty) {
      continue;
    }
    final String suffix = entry.key.substring(prefix.length);
    final List<String> path = suffix.split('__');
    if (suffix.isEmpty || path.any((String segment) => segment.isEmpty)) {
      throw EnvironmentCoercionException(
        key: entry.key,
        reason: 'must contain non-empty __-separated path components',
      );
    }
    _insertPath(root, path, coerceEnvironmentScalar(entry.value), entry.key);
  }

  return _materializeCollections(root, '<root>')! as JsonObject;
}

void _insertPath(
  JsonObject root,
  List<String> path,
  Object? value,
  String sourceKey,
) {
  JsonObject cursor = root;
  for (int index = 0; index < path.length; index += 1) {
    final String segment = path[index].toLowerCase();
    final bool isLeaf = index == path.length - 1;
    if (isLeaf) {
      if (cursor.containsKey(segment)) {
        throw EnvironmentCoercionException(
          key: sourceKey,
          reason: 'duplicates a normalized configuration path',
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
      throw EnvironmentCoercionException(
        key: sourceKey,
        reason: 'collides with a scalar configuration path',
      );
    }
  }
}

Object? _materializeCollections(Object? value, String path) {
  if (value is! JsonObject) {
    return deepClone(value);
  }

  final bool hasNumericKey = value.keys.any(_isIndex);
  if (hasNumericKey && !value.keys.every(_isIndex)) {
    throw EnvironmentCoercionException(
      key: path,
      reason: 'mixes indexed and named child keys',
    );
  }
  if (hasNumericKey) {
    final List<int> indexes = value.keys.map(int.parse).toList()..sort();
    for (int expected = 0; expected < indexes.length; expected += 1) {
      if (indexes[expected] != expected) {
        throw EnvironmentCoercionException(
          key: path,
          reason: 'uses sparse list indexes; expected $expected',
        );
      }
    }
    return <Object?>[
      for (final int index in indexes)
        _materializeCollections(value['$index'], '${path}__$index'),
    ];
  }

  return <String, Object?>{
    for (final MapEntry<String, Object?> entry in value.entries)
      entry.key: _materializeCollections(
        entry.value,
        '${path}__${entry.key}',
      ),
  };
}

bool _isIndex(String value) => RegExp(r'^(?:0|[1-9]\d*)$').hasMatch(value);
