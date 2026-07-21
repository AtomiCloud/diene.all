import 'dart:convert';
import 'dart:io';

import 'package:diene_config/diene_config.dart';
import 'package:test/test.dart';

import '../support.dart';

void main() {
  final Map<String, Object?> fixture = _fixture();
  final Map<String, Object?> provenance = _map(fixture['provenance']);
  final Map<String, Object?> cases = _map(fixture['cases']);

  test('C0 fixture is bound to the authoritative config contract', () {
    // Arrange.
    final List<Object?> sources =
        provenance['authoritativeSources']! as List<Object?>;

    // Act.
    final Set<String> paths = sources
        .map((Object? source) => _map(source)['path']! as String)
        .toSet();

    // Assert.
    expect(paths, <String>{
      'goals/c0-contracts.md',
      'goals/lib/dart-family.md',
    });
    expect(provenance['replacementAndRegreen'], isA<List<Object?>>());
  });

  test(
    'C0 layers base, landscape, development, then dart-define last',
    () async {
      final Map<String, Object?> scenario = _map(
        cases['layeringAndIndexedList'],
      );
      // Arrange. The base is intentionally invalid until later layers repair it;
      // proving intermediate layers are not validated.
      final ConfigLoader loader = ConfigLoader(
        base: YamlConfigSource.string(scenario['baseYaml']! as String),
        overlay: YamlConfigSource.string(scenario['landscapeYaml']! as String),
        developmentOverride: YamlConfigSource.string(
          scenario['developmentYaml']! as String,
        ),
        dartDefines: DartDefineOverrides(
          prefix: scenario['prefix']! as String,
          values: _strings(scenario['defines']),
        ),
        schema: appSchema(),
      );

      // Act.
      final DieneConfig config = await loader.load();

      // Assert.
      final AppBlock app = config.slice(appBlock);
      final Map<String, Object?> expected = _map(scenario['expected']);
      expect(app.name, expected['name']);
      expect(app.retries, expected['retries']);
      expect(app.tags, expected['tags']);
    },
  );

  test('C0 treats blank Dart defines as unset', () async {
    final Map<String, Object?> scenario = _map(cases['blankIsUnset']);
    // Arrange.
    final ConfigLoader loader = ConfigLoader(
      base: YamlConfigSource.string(scenario['baseYaml']! as String),
      dartDefines: DartDefineOverrides(
        prefix: scenario['prefix']! as String,
        values: _strings(scenario['defines']),
      ),
      schema: appSchema(),
    );

    // Act.
    final AppBlock app = (await loader.load()).slice(appBlock);

    // Assert.
    final Map<String, Object?> expected = _map(scenario['expected']);
    expect(app.name, expected['name']);
    expect(app.retries, expected['retries']);
    expect(app.tags, expected['tags']);
  });

  for (final Object? item
      in cases['invalidCollectionEncodings']! as List<Object?>) {
    final Map<String, Object?> scenario = _map(item);
    test('C0 rejects ${scenario['name']} list overrides', () {
      // Arrange.
      final ConfigLoader loader = ConfigLoader(
        base: YamlConfigSource.string(scenario['baseYaml']! as String),
        dartDefines: DartDefineOverrides(
          prefix: scenario['prefix']! as String,
          values: _strings(scenario['defines']),
        ),
        schema: appSchema(),
      );

      // Act and assert.
      expect(loader.load, throwsA(isA<ConfigValidationException>()));
    });
  }

  test('C0 validation fails before an invalid final config is exposed', () {
    final Map<String, Object?> scenario = _map(cases['invalidFinal']);
    // Arrange.
    final ConfigLoader loader = ConfigLoader(
      base: YamlConfigSource.string(scenario['baseYaml']! as String),
      dartDefines: DartDefineOverrides(
        prefix: scenario['prefix']! as String,
        values: _strings(scenario['defines']),
      ),
      schema: appSchema(),
    );

    // Act and assert.
    expect(loader.load, throwsA(isA<ConfigValidationException>()));
  });
}

Map<String, Object?> _fixture() =>
    _map(jsonDecode(File('test/fixtures/c0_config.json').readAsStringSync()));

Map<String, Object?> _map(Object? value) =>
    Map<String, Object?>.from(value! as Map<String, dynamic>);

Map<String, String> _strings(Object? value) =>
    Map<String, String>.from(value! as Map<String, dynamic>);
