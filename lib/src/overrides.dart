import 'deep_merge.dart';

/// Compile-time values passed with `--dart-define`.
///
/// Applications must enumerate their defines with `String.fromEnvironment`
/// because Dart does not expose the full compile-time environment at runtime.
/// Empty values are treated as unset. [prefix] is deliberately required and
/// app-owned; this package has no family-wide environment prefix.
final class DartDefineOverrides {
  DartDefineOverrides({
    required this.prefix,
    required Map<String, String> values,
  }) : values = Map<String, String>.unmodifiable(values) {
    if (prefix.isEmpty) {
      throw ArgumentError.value(prefix, 'prefix', 'must not be empty');
    }
  }

  final String prefix;
  final Map<String, String> values;

  /// Applies these values after every YAML layer.
  Map<String, Object?> apply(Map<String, Object?> input) =>
      applyIndexedOverrides(input, values: values, prefix: prefix);
}

/// Applies prefixed, `__`-nested overrides to [input].
///
/// Key matching ignores case and `-`/`_`, so snake, kebab, camel, and Pascal
/// spellings resolve to the key already authored in the full base YAML.
/// Numeric segments encode lists (`SCOPES__0`, `SCOPES__1`, ...). The first
/// indexed override replaces the previous list, and indexes must be contiguous.
/// JSON and comma-separated list encodings are intentionally unsupported.
Map<String, Object?> applyIndexedOverrides(
  Map<String, Object?> input, {
  required Map<String, String> values,
  required String prefix,
}) {
  if (prefix.isEmpty) {
    throw ArgumentError.value(prefix, 'prefix', 'must not be empty');
  }
  final Map<String, Object?> result = deepMerge(
    const <String, Object?>{},
    input,
  );
  final List<_Override> overrides =
      values.entries
          .where((MapEntry<String, String> entry) {
            final String key = entry.key;
            return key.length > prefix.length &&
                key.substring(0, prefix.length).toLowerCase() ==
                    prefix.toLowerCase() &&
                entry.value.isNotEmpty;
          })
          .map(
            (MapEntry<String, String> entry) => _Override(
              entry.key,
              entry.key.substring(prefix.length).split('__'),
              _coerce(entry.value),
            ),
          )
          .toList(growable: false)
        ..sort(_compareOverrides);

  final Set<String> replacedLists = <String>{};
  for (final _Override override in overrides) {
    if (override.segments.any((String segment) => segment.isEmpty)) {
      throw ConfigOverrideException(
        override.name,
        'contains an empty path segment',
      );
    }
    _apply(
      result,
      override,
      position: 0,
      canonicalPath: '',
      replacedLists: replacedLists,
    );
  }
  return result;
}

void _apply(
  Object? current,
  _Override override, {
  required int position,
  required String canonicalPath,
  required Set<String> replacedLists,
}) {
  final String segment = override.segments[position];
  final bool last = position == override.segments.length - 1;

  if (current is Map<String, Object?>) {
    final String key = _matchingKey(
      current,
      segment,
      override.name,
      allowNew: canonicalPath.contains('['),
    );
    if (last) {
      current[key] = override.value;
      return;
    }
    final Object? child = current[key];
    if (child is! Map<String, Object?> && child is! List<Object?>) {
      throw ConfigOverrideException(
        override.name,
        'cannot descend through scalar key $key',
      );
    }
    _apply(
      child,
      override,
      position: position + 1,
      canonicalPath: canonicalPath.isEmpty ? key : '$canonicalPath.$key',
      replacedLists: replacedLists,
    );
    return;
  }

  if (current is List<Object?>) {
    final int? index = int.tryParse(segment);
    if (index == null || index < 0) {
      throw ConfigOverrideException(
        override.name,
        'list segment $segment is not a non-negative index',
      );
    }
    if (replacedLists.add(canonicalPath)) {
      current.clear();
    }
    if (index > current.length) {
      throw ConfigOverrideException(
        override.name,
        'list indexes must be contiguous from 0',
      );
    }
    if (last) {
      if (index == current.length) {
        current.add(override.value);
      } else {
        current[index] = override.value;
      }
      return;
    }
    if (index == current.length) {
      final Object next = int.tryParse(override.segments[position + 1]) == null
          ? <String, Object?>{}
          : <Object?>[];
      current.add(next);
    }
    final Object? child = current[index];
    if (child is! Map<String, Object?> && child is! List<Object?>) {
      throw ConfigOverrideException(
        override.name,
        'cannot descend through scalar list item $index',
      );
    }
    _apply(
      child,
      override,
      position: position + 1,
      canonicalPath: '$canonicalPath[$index]',
      replacedLists: replacedLists,
    );
    return;
  }

  throw ConfigOverrideException(override.name, 'targets an unsupported value');
}

String _matchingKey(
  Map<String, Object?> map,
  String requested,
  String overrideName, {
  required bool allowNew,
}) {
  final String normalized = _normalize(requested);
  final List<String> matches = map.keys
      .where((String key) => _normalize(key) == normalized)
      .toList(growable: false);
  if (matches.isEmpty && allowNew) {
    return _authoredKey(requested);
  }
  if (matches.length != 1) {
    final String reason = matches.isEmpty
        ? 'does not match a key in the full base configuration'
        : 'matches multiple keys after normalization';
    throw ConfigOverrideException(overrideName, '$requested $reason');
  }
  return matches.single;
}

String _authoredKey(String value) {
  final List<String> words = value
      .toLowerCase()
      .split(RegExp('[-_]'))
      .where((String word) => word.isNotEmpty)
      .toList(growable: false);
  return <String>[
    words.first,
    ...words
        .skip(1)
        .map((String word) => '${word[0].toUpperCase()}${word.substring(1)}'),
  ].join();
}

String _normalize(String value) =>
    value.replaceAll(RegExp('[-_]'), '').toLowerCase();

Object _coerce(String value) {
  final String lower = value.toLowerCase();
  if (lower == 'true') {
    return true;
  }
  if (lower == 'false') {
    return false;
  }
  return int.tryParse(value) ?? double.tryParse(value) ?? value;
}

int _compareOverrides(_Override left, _Override right) {
  final int common = left.segments.length < right.segments.length
      ? left.segments.length
      : right.segments.length;
  for (int index = 0; index < common; index += 1) {
    final String a = left.segments[index];
    final String b = right.segments[index];
    final int? ai = int.tryParse(a);
    final int? bi = int.tryParse(b);
    final int comparison = ai != null && bi != null
        ? ai.compareTo(bi)
        : a.compareTo(b);
    if (comparison != 0) {
      return comparison;
    }
  }
  return left.segments.length.compareTo(right.segments.length);
}

final class _Override {
  const _Override(this.name, this.segments, this.value);

  final String name;
  final List<String> segments;
  final Object value;
}

/// Indicates an invalid or unknown Dart-define path.
final class ConfigOverrideException implements Exception {
  const ConfigOverrideException(this.name, this.message);

  final String name;
  final String message;

  @override
  String toString() => 'ConfigOverrideException($name): $message';
}
