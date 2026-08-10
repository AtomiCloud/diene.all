/// The layered loader: the C0 §3 precedence ladder, run exactly once.
///
/// Layer order is fixed and total:
///
/// 1. **base** — a full YAML document defining every overrideable path;
/// 2. **overlay** — one sparse flavor/landscape YAML;
/// 3. **development override** — an optional local hook;
/// 4. **Dart defines** — enumerated `--dart-define` values, applied LAST;
/// 5. **validate** — the composed schema, against the final tree only.
///
/// Nothing between steps 1 and 4 is validated or exposed. A base layer that is
/// incomplete on its own is not an error if a later layer completes it.
library;

import 'package:diene_core_utils/diene_core_utils.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';

import 'config_source.dart';
import 'schema.dart';

/// Enumerated `--dart-define` values contributing the last layer.
///
/// Dart has no runtime environment enumeration — `String.fromEnvironment` is a
/// compile-time lookup of a key that must be written literally — so an
/// application ENUMERATES the defines it accepts and passes them here. That is
/// a deliberate delta from the Bun sibling, which reads `process.env` wholesale.
///
/// The decoding itself is not implemented here: [environmentToNestedMap] from
/// `diene_core_utils` owns the C0 §3 rules (`__` path separator, all-digit
/// components build lists, blank means UNSET, no JSON and no comma decoding).
final class DartDefineOverrides {
  /// Creates an override layer over the [prefix]-scoped entries of [values].
  const DartDefineOverrides({
    required this.prefix,
    this.values = const <String, String>{},
  });

  /// Application-owned key prefix, matched case-insensitively.
  final String prefix;

  /// The enumerated define keys and their build-time values.
  final Map<String, String> values;

  /// Projects the defines into a nested configuration layer.
  ///
  /// A rejection (an empty path component, a duplicate normalised path, a
  /// scalar used as a parent, a sparse or mixed list) is returned as the
  /// `diene_core_utils` `Problem` UNCHANGED, so its coercion vocabulary
  /// survives instead of being re-minted under a config code that would say
  /// less.
  Result<JsonObject> layer() => environmentToNestedMap(values, prefix: prefix);
}

/// Loads and validates a layered configuration.
///
/// [load] is the primary surface and never throws for an expected failure:
/// an unreadable layer, a malformed define key, and an invalid final tree are
/// all `Err` values carrying an RFC 9457 `Problem`.
final class ConfigLoader {
  /// Creates a loader over the given layers and composed [schema].
  const ConfigLoader({
    required this.base,
    required this.schema,
    required this.dartDefines,
    this.overlay,
    this.developmentOverride,
  });

  /// The full base layer.
  final ConfigSource base;

  /// The sparse flavor/landscape layer, if any.
  final ConfigSource? overlay;

  /// The optional development hook, applied after [overlay].
  final ConfigSource? developmentOverride;

  /// The `--dart-define` layer, applied last.
  final DartDefineOverrides dartDefines;

  /// The service-composed root schema.
  final ConfigSchema schema;

  /// Loads every layer in precedence order and validates the final tree once.
  Future<Result<DieneConfig>> load() async {
    final List<JsonObject> layers = <JsonObject>[];

    for (final ConfigSource? source in <ConfigSource?>[
      base,
      overlay,
      developmentOverride,
    ]) {
      if (source == null) {
        continue;
      }
      switch (await source.load()) {
        case Ok<JsonObject>(value: final JsonObject layer):
          layers.add(layer);
        case Err<JsonObject>(problem: final Problem problem):
          // Short-circuit: a later layer cannot repair a layer that never
          // parsed, and merging on would validate a tree the caller never
          // described.
          return Err<DieneConfig>(problem);
      }
    }

    switch (dartDefines.layer()) {
      case Ok<JsonObject>(value: final JsonObject defines):
        layers.add(defines);
      case Err<JsonObject>(problem: final Problem problem):
        return Err<DieneConfig>(problem);
    }

    // deepMergeAll IS the precedence ladder: a fold in layer order, with
    // case-insensitive key matching and the base layer's spelling winning.
    return schema.validate(deepMergeAll(layers));
  }
}
