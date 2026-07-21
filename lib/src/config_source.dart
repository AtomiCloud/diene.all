import 'dart:async';

import 'package:yaml/yaml.dart';

/// Supplies one YAML-shaped configuration layer.
abstract interface class ConfigSource {
  Future<Map<String, Object?>> load();
}

/// Reads a YAML layer without depending on `dart:io` or Flutter.
///
/// A command-line app can pass `File(path).readAsString`; Flutter can pass
/// `rootBundle.loadString(path)`.
final class YamlConfigSource implements ConfigSource {
  const YamlConfigSource({required this.read, required this.name});

  /// Creates a source backed by an already available YAML document.
  factory YamlConfigSource.string(String document, {String name = 'memory'}) =>
      YamlConfigSource(read: () => document, name: name);

  final FutureOr<String> Function() read;
  final String name;

  @override
  Future<Map<String, Object?>> load() async {
    try {
      final Object? document = loadYaml(await read());
      return _plainMap(document);
    } on ConfigSourceException {
      rethrow;
    } on Object catch (error) {
      throw ConfigSourceException(name, 'could not be read: $error');
    }
  }

  Map<String, Object?> _plainMap(Object? value) {
    if (value is! Map<Object?, Object?>) {
      throw ConfigSourceException(name, 'root must be a map');
    }
    return value.map(
      (Object? key, Object? item) =>
          MapEntry<String, Object?>(key.toString(), _plainValue(item)),
    );
  }

  Object? _plainValue(Object? value) => switch (value) {
    final Map<Object?, Object?> map => map.map(
      (Object? key, Object? item) =>
          MapEntry<String, Object?>(key.toString(), _plainValue(item)),
    ),
    final List<Object?> list =>
      list.map<Object?>(_plainValue).toList(growable: false),
    _ => value,
  };
}

/// Indicates that a configuration layer could not be loaded.
final class ConfigSourceException implements Exception {
  const ConfigSourceException(this.source, this.message);

  final String source;
  final String message;

  @override
  String toString() => 'ConfigSourceException($source): $message';
}
