/// Service-composed root schema, final-layer validation, and typed slices.
///
/// `diene_config` owns COMPOSITION mechanics, not schemas. An engine package
/// (auth-engine, api-engine, …) exports its own [ConfigBlock] beside the code
/// that reads it; the application assembles those blocks — plus its own — into
/// one [ConfigSchema]. This library never defines another library's block.
///
/// Validation happens EXACTLY ONCE, against the final merged tree. No
/// intermediate layer is validated, and no intermediate layer is ever exposed:
/// a base YAML that is invalid on its own but completed by an overlay is
/// correct, and the loader must not reject it midway.
library;

import 'dart:collection';

import 'package:diene_core_utils/diene_core_utils.dart';
import 'package:diene_result/diene_result.dart';

import 'config_problem.dart';

/// Type-erased view of a [ConfigBlock], so differently typed engine blocks
/// compose into one list.
///
/// A caller implements [ConfigBlock] rather than this interface; it exists
/// because `ConfigBlock<AuthSettings>` and `ConfigBlock<ApiSettings>` have no
/// common supertype otherwise.
abstract interface class ConfigBlockSchema {
  /// Root key this block decodes, in the spelling its owner authored.
  String get key;

  /// Whether the final configuration must contain this block.
  bool get required;

  /// Decodes [value] without exposing the block's static type.
  Object? decodeUntyped(Map<String, Object?> value);
}

/// Converts and validates one engine- or service-owned configuration block.
///
/// [decode] is the OWNER's validation: it receives the final merged block and
/// either returns the typed value or throws. Throwing is correct here and is
/// the only place this library expects it — a decoder is a plain callback
/// written by a consumer, so demanding a `Result` return would force every
/// engine to depend on `diene_result` merely to describe its own settings.
/// [ConfigSchema.validate] catches each throw and folds it into ONE aggregate
/// problem, so a caller still never sees an exception escape.
final class ConfigBlock<T> implements ConfigBlockSchema {
  /// Creates a block decoding the root [key].
  const ConfigBlock({
    required this.key,
    required this.decode,
    this.required = true,
  });

  @override
  final String key;

  /// Turns the block's final merged map into its typed value.
  final T Function(Map<String, Object?> values) decode;

  @override
  final bool required;

  @override
  Object? decodeUntyped(Map<String, Object?> value) => decode(value);
}

/// A root schema assembled by the service from engine-owned blocks and its own.
final class ConfigSchema {
  /// Composes [blocks] into a root schema.
  ///
  /// Throws [ArgumentError] on an empty, reserved, or duplicate block key.
  /// That is programmer misuse — the block list is source code, not input —
  /// so it is the one construction that throws rather than returning a value.
  ConfigSchema({
    required Iterable<ConfigBlockSchema> blocks,
    this.rejectUnknownBlocks = true,
  }) : _blocks = List<ConfigBlockSchema>.unmodifiable(blocks) {
    _validateBlockKeys();
  }

  final List<ConfigBlockSchema> _blocks;

  /// Whether a root key with no composed block is an error.
  ///
  /// Defaults to `true`: an unknown root key is nearly always a typo, and
  /// silently ignoring it is how a misspelled setting reaches production.
  final bool rejectUnknownBlocks;

  /// The composed blocks, in composition order.
  List<ConfigBlockSchema> get blocks => _blocks;

  /// Validates the FINAL merged configuration and builds its typed slices.
  ///
  /// Every problem found is collected before returning, so one pass reports
  /// every misconfiguration rather than only the first.
  Result<DieneConfig> validate(Map<String, Object?> values) {
    final Map<String, String> actualKeys = <String, String>{};
    final List<String> errors = <String>[];

    for (final String key in values.keys) {
      if (key == _schemaKey) {
        continue;
      }
      final String canonical = canonicalConfigKey(key);
      final String? existing = actualKeys[canonical];
      if (existing != null) {
        errors.add('root keys $existing and $key collide');
      } else {
        actualKeys[canonical] = key;
      }
    }

    final Map<String, Object?> decoded = <String, Object?>{};
    final Set<String> declared = <String>{};
    for (final ConfigBlockSchema block in _blocks) {
      final String canonical = canonicalConfigKey(block.key);
      declared.add(canonical);
      final String? actual = actualKeys[canonical];
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
        decoded[canonical] = block.decodeUntyped(raw);
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
      return configFailure<DieneConfig>(
        code: ConfigProblemCode.schemaInvalid,
        message: 'final configuration failed validation',
        details: <String, Object?>{'errors': List<String>.unmodifiable(errors)},
      );
    }
    return Ok<DieneConfig>(
      DieneConfig._(
        _freezeMap(values),
        Map<String, Object?>.unmodifiable(decoded),
      ),
    );
  }

  void _validateBlockKeys() {
    final Set<String> seen = <String>{};
    for (final ConfigBlockSchema block in _blocks) {
      if (block.key.isEmpty || block.key == _schemaKey) {
        throw ArgumentError.value(block.key, 'blocks', 'invalid block key');
      }
      if (!seen.add(canonicalConfigKey(block.key))) {
        throw ArgumentError.value(block.key, 'blocks', 'duplicate block key');
      }
    }
  }
}

/// An immutable, validated configuration and its typed block slices.
///
/// There is no watch or reload API: configuration is loaded once and is
/// constant for the life of the process.
final class DieneConfig {
  const DieneConfig._(this.raw, this._decoded);

  /// The final merged tree, deeply unmodifiable.
  final Map<String, Object?> raw;

  final Map<String, Object?> _decoded;

  /// Returns the typed value produced by [block]'s owner-supplied decoder.
  ///
  /// Throws [StateError] when [block] was not part of the composed schema, or
  /// when it is an optional block the final configuration omitted. Both are
  /// programmer misuse — asking for a slice that structurally cannot exist —
  /// so they throw rather than returning a failure value. Use [hasSlice] to
  /// branch on an optional block instead.
  T slice<T>(ConfigBlock<T> block) {
    final String canonical = canonicalConfigKey(block.key);
    if (!_decoded.containsKey(canonical)) {
      throw StateError('Configuration block ${block.key} was not composed');
    }
    return _decoded[canonical] as T;
  }

  /// Whether [block] was composed AND present in the final configuration.
  bool hasSlice(ConfigBlockSchema block) =>
      _decoded.containsKey(canonicalConfigKey(block.key));

  /// Returns [slice] when the block is present, or `None` when it is not.
  Option<T> optionalSlice<T>(ConfigBlock<T> block) =>
      hasSlice(block) ? Some<T>(slice<T>(block)) : None<T>();

  /// Returns an immutable untyped view of one final merged block.
  ///
  /// Useful for a block nobody has written a decoder for yet. Matching is
  /// case- and separator-insensitive, exactly like [slice].
  Result<Map<String, Object?>> rawSlice(String key) {
    final String canonical = canonicalConfigKey(key);
    for (final MapEntry<String, Object?> entry in raw.entries) {
      if (canonicalConfigKey(entry.key) != canonical) {
        continue;
      }
      final Object? value = entry.value;
      if (value is! Map<String, Object?>) {
        return configFailure<Map<String, Object?>>(
          code: ConfigProblemCode.schemaInvalid,
          message: 'configuration block $key is not a map',
          details: <String, Object?>{'block': key},
        );
      }
      return Ok<Map<String, Object?>>(value);
    }
    return configFailure<Map<String, Object?>>(
      code: ConfigProblemCode.schemaInvalid,
      message: 'configuration block $key was not loaded',
      details: <String, Object?>{'block': key},
    );
  }

  /// A deterministic projection of [raw] — sorted keys at every depth.
  ///
  /// Delegates to `stableConfig` from `diene_core_utils` so two structurally
  /// equal configurations hash and diff identically.
  Result<Object?> stableProjection() => stableConfig(raw);
}

const String _schemaKey = r'$schema';

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
