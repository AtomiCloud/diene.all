/// Dependency-light fakes and builders for `package:diene_config` consumers.
library;

import 'dart:async';

import 'diene_config.dart';

/// In-memory configuration layer with observable load behavior.
final class FakeConfigSource implements ConfigSource {
  FakeConfigSource(Map<String, Object?> values)
    : _values = Map<String, Object?>.unmodifiable(values);

  final Map<String, Object?> _values;
  int loadCount = 0;

  @override
  Future<Map<String, Object?>> load() async {
    loadCount += 1;
    return deepMerge(const <String, Object?>{}, _values);
  }
}

/// Deterministic landscape source for tests.
final class FakeLandscapeSource implements LandscapeSource {
  const FakeLandscapeSource(this.value);

  final String value;

  @override
  String read() => value;
}

/// Builds a validated configuration stub through the production schema path.
final class ConfigStubBuilder {
  final Map<String, Object?> _raw = <String, Object?>{};
  final List<ConfigBlockSchema> _blocks = <ConfigBlockSchema>[];

  ConfigStubBuilder add<T>(
    ConfigBlock<T> block,
    Map<String, Object?> rawValues,
  ) {
    _blocks.add(block);
    _raw[block.key] = rawValues;
    return this;
  }

  DieneConfig build({bool rejectUnknownBlocks = true}) => ConfigSchema(
    blocks: _blocks,
    rejectUnknownBlocks: rejectUnknownBlocks,
  ).validate(_raw);
}

/// Convenience harness for exercising the full production layer order with
/// in-memory sources.
final class FakeConfigHarness {
  FakeConfigHarness({
    required this.base,
    required this.schema,
    this.overlay = const <String, Object?>{},
    this.developmentOverride = const <String, Object?>{},
    this.defines = const <String, String>{},
    this.prefix = 'TEST_',
  });

  final Map<String, Object?> base;
  final Map<String, Object?> overlay;
  final Map<String, Object?> developmentOverride;
  final Map<String, String> defines;
  final String prefix;
  final ConfigSchema schema;

  Future<DieneConfig> load() => ConfigLoader(
    base: FakeConfigSource(base),
    overlay: FakeConfigSource(overlay),
    developmentOverride: FakeConfigSource(developmentOverride),
    dartDefines: DartDefineOverrides(prefix: prefix, values: defines),
    schema: schema,
  ).load();
}
