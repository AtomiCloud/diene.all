import 'dart:collection';

/// Type-erased view used to compose differently typed engine blocks.
abstract interface class ConfigBlockSchema {
  String get key;
  bool get required;
  Object? decodeUntyped(Map<String, Object?> value);
}

/// Converts and validates one engine- or service-owned configuration block.
///
/// Engine packages export their own instances beside the code that consumes
/// them. `diene_config` provides composition mechanics but owns no engine
/// block schemas.
final class ConfigBlock<T> implements ConfigBlockSchema {
  const ConfigBlock({
    required this.key,
    required this.decode,
    this.required = true,
  });

  @override
  final String key;
  final T Function(Map<String, Object?> values) decode;
  @override
  final bool required;

  @override
  Object? decodeUntyped(Map<String, Object?> value) => decode(value);
}

/// A service-composed root schema assembled from engine-owned blocks and the
/// service's own blocks.
final class ConfigSchema {
  ConfigSchema({
    required Iterable<ConfigBlockSchema> blocks,
    this.rejectUnknownBlocks = true,
  }) : _blocks = blocks.toList(growable: false) {
    _validateBlockKeys();
  }

  final List<ConfigBlockSchema> _blocks;
  final bool rejectUnknownBlocks;

  /// Validates the final merged configuration and builds its typed slices.
  DieneConfig validate(Map<String, Object?> values) {
    final Map<String, String> actualKeys = <String, String>{};
    final List<String> errors = <String>[];
    for (final String key in values.keys) {
      if (key == r'$schema') {
        continue;
      }
      final String normalized = _normalize(key);
      if (actualKeys.containsKey(normalized)) {
        errors.add('root keys ${actualKeys[normalized]} and $key collide');
      } else {
        actualKeys[normalized] = key;
      }
    }

    final Map<String, Object?> decoded = <String, Object?>{};
    final Set<String> declared = <String>{};
    for (final ConfigBlockSchema block in _blocks) {
      final String normalized = _normalize(block.key);
      declared.add(normalized);
      final String? actual = actualKeys[normalized];
      if (actual == null) {
        if (block.required) {
          errors.add('${block.key}: required block is missing');
        }
        continue;
      }
      final Object? raw = values[actual];
      if (raw is! Map<String, Object?>) {
        errors.add('${block.key}: block must be a map');
        continue;
      }
      try {
        decoded[normalized] = block.decodeUntyped(raw);
      } on Object catch (error) {
        errors.add('${block.key}: $error');
      }
    }

    if (rejectUnknownBlocks) {
      for (final MapEntry<String, String> entry in actualKeys.entries) {
        if (!declared.contains(entry.key)) {
          errors.add('${entry.value}: no composed block schema');
        }
      }
    }
    if (errors.isNotEmpty) {
      throw ConfigValidationException(errors);
    }
    return DieneConfig._(_freezeMap(values), Map.unmodifiable(decoded));
  }

  void _validateBlockKeys() {
    final Set<String> keys = <String>{};
    for (final ConfigBlockSchema block in _blocks) {
      if (block.key.isEmpty || block.key == r'$schema') {
        throw ArgumentError.value(block.key, 'blocks', 'invalid block key');
      }
      if (!keys.add(_normalize(block.key))) {
        throw ArgumentError.value(block.key, 'blocks', 'duplicate block key');
      }
    }
  }
}

/// Immutable validated configuration and its typed block slices.
final class DieneConfig {
  const DieneConfig._(this.raw, this._decoded);

  final Map<String, Object?> raw;
  final Map<String, Object?> _decoded;

  /// Returns the typed value produced by [block]'s engine-owned decoder.
  T slice<T>(ConfigBlock<T> block) {
    final String key = _normalize(block.key);
    if (!_decoded.containsKey(key)) {
      throw StateError('Configuration block ${block.key} was not composed');
    }
    return _decoded[key] as T;
  }

  /// Returns an immutable untyped view of one final merged block.
  Map<String, Object?> rawSlice(String key) {
    final String normalized = _normalize(key);
    final String actual = raw.keys.firstWhere(
      (String candidate) => _normalize(candidate) == normalized,
      orElse: () => throw StateError('Configuration block $key was not loaded'),
    );
    final Object? value = raw[actual];
    if (value is! Map<String, Object?>) {
      throw StateError('Configuration block $key is not a map');
    }
    return value;
  }
}

/// Contains every schema error found in the final merged configuration.
final class ConfigValidationException implements Exception {
  ConfigValidationException(Iterable<String> errors)
    : errors = List<String>.unmodifiable(errors);

  final List<String> errors;

  @override
  String toString() =>
      'Configuration validation failed:\n- ${errors.join('\n- ')}';
}

String _normalize(String value) =>
    value.replaceAll(RegExp('[-_]'), '').toLowerCase();

Map<String, Object?> _freezeMap(Map<String, Object?> value) =>
    UnmodifiableMapView<String, Object?>(
      value.map(
        (String key, Object? item) =>
            MapEntry<String, Object?>(key, _freeze(item)),
      ),
    );

Object? _freeze(Object? value) => switch (value) {
  final Map<String, Object?> map => _freezeMap(map),
  final List<Object?> list => List<Object?>.unmodifiable(list.map(_freeze)),
  _ => value,
};
