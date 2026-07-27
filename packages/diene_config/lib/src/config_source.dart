/// One configuration layer and the YAML reader that produces it.
///
/// YAML parsing is the ONE mechanic `diene_config` owns outright: the merge,
/// key canonicalisation, and environment coercion all come from
/// `package:diene_core_utils`, but no upstream Dart-family package ships a
/// parser, so this is where the bytes become a [JsonObject].
///
/// The reader takes a text CALLBACK rather than a path, so this library imports
/// neither `dart:io` nor Flutter and runs unchanged on the VM, on the web, and
/// in Flutter. A command-line app passes `File(path).readAsString`; Flutter
/// passes `rootBundle.loadString(path)`.
library;

import 'dart:async';

import 'package:diene_core_utils/diene_core_utils.dart';
import 'package:diene_result/diene_result.dart';
import 'package:yaml/yaml.dart';

import 'config_problem.dart';

/// Supplies one YAML-shaped configuration layer.
///
/// Every implementation reports failure as a `Result` value; a layer that
/// cannot be read is an EXPECTED outcome (a missing asset, a typo in a YAML
/// document), not a programmer error.
abstract interface class ConfigSource {
  /// Loads this layer, or reports why it could not be loaded.
  Future<Result<JsonObject>> load();
}

/// Reads a YAML layer through an injected text callback.
///
/// The callback may be synchronous or asynchronous ([FutureOr]), so an
/// in-memory document and a bundle/file read use the same source type.
final class YamlConfigSource implements ConfigSource {
  /// Creates a source that reads its document through [read].
  ///
  /// [name] identifies the layer in failure envelopes; it is a diagnostic
  /// label, not a path the source itself resolves.
  const YamlConfigSource({required this.read, required this.name});

  /// Creates a source backed by an already available YAML [document].
  factory YamlConfigSource.string(String document, {String name = 'memory'}) =>
      YamlConfigSource(read: () => document, name: name);

  /// Produces the layer's YAML text.
  final FutureOr<String> Function() read;

  /// Diagnostic label for this layer.
  final String name;

  @override
  Future<Result<JsonObject>> load() async {
    final Object? document;
    try {
      document = loadYaml(await read());
    } on Object catch (error) {
      // Both a failing read callback and a YAML syntax error land here. They
      // are the same thing to a caller — this layer did not produce a
      // document — so they share one code and name the layer in `data`.
      return configFailure<JsonObject>(
        code: ConfigProblemCode.sourceUnreadable,
        message: 'configuration layer $name could not be read',
        details: <String, Object?>{'source': name, 'reason': '$error'},
      );
    }

    // An empty YAML document parses to null, which is a layer that contributes
    // nothing rather than a malformed one.
    if (document == null) {
      return Ok<JsonObject>(<String, Object?>{});
    }
    if (document is! Map<Object?, Object?>) {
      return configFailure<JsonObject>(
        code: ConfigProblemCode.sourceNotAMap,
        message: 'configuration layer $name must have a map at its root',
        details: <String, Object?>{'source': name},
      );
    }
    return Ok<JsonObject>(_plainMap(document));
  }

  /// Converts a `YamlMap` tree into plain `Map`/`List` collections.
  ///
  /// The `yaml` package's own collection types are unmodifiable views that do
  /// not satisfy `Map<String, Object?>`, so `deepMerge` would treat them as
  /// opaque scalars and REPLACE instead of merging. Non-string keys are
  /// rendered with `toString()`: YAML permits them, C0 §3 configuration paths
  /// do not, and a `1:` key is far more likely a typo than an intent.
  JsonObject _plainMap(Map<Object?, Object?> value) => value.map(
    (Object? key, Object? item) =>
        MapEntry<String, Object?>(key.toString(), _plainValue(item)),
  );

  Object? _plainValue(Object? value) => switch (value) {
    final Map<Object?, Object?> map => _plainMap(map),
    final List<Object?> list =>
      list.map<Object?>(_plainValue).toList(growable: false),
    _ => value,
  };
}
