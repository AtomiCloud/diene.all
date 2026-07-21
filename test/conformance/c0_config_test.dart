import 'dart:convert';
import 'dart:io';

import 'package:diene_config/diene_config.dart';
import 'package:test/test.dart';

import '../support.dart';

void main() {
  test('generated projection identity names the authenticated release', () {
    final Map<String, Object?> projection = _map(
      jsonDecode(File('test/fixtures/c0/config.json').readAsStringSync()),
    );
    final Map<String, Object?> generated = _map(projection[r'$generated']);

    expect(generated['generator'], 'tool/gen_c0_projection.dart');
    expect(generated['releaseId'], c0ConfigContract.provenance.releaseId);
    expect(
      generated['releaseDigest'],
      c0ConfigContract.provenance.releaseDigest,
    );
    expect(projection['domain'], 'config');
    expect(projection['c0Sections'], c0ConfigContract.c0Sections);
  });

  test(
    'C0 layers base, landscape, development, then dart-define last',
    () async {
      final Map<String, Object?> scenario =
          c0ConfigContract.layeringAndIndexedList;
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

      final AppBlock app = (await loader.load()).slice(appBlock);

      final Map<String, Object?> expected = _map(scenario['expected']);
      expect(app.name, expected['name']);
      expect(app.retries, expected['retries']);
      expect(app.tags, expected['tags']);
    },
  );

  test('C0 treats blank Dart defines as unset', () async {
    final Map<String, Object?> scenario = c0ConfigContract.blankIsUnset;
    final ConfigLoader loader = ConfigLoader(
      base: YamlConfigSource.string(scenario['baseYaml']! as String),
      dartDefines: DartDefineOverrides(
        prefix: scenario['prefix']! as String,
        values: _strings(scenario['defines']),
      ),
      schema: appSchema(),
    );

    final AppBlock app = (await loader.load()).slice(appBlock);

    final Map<String, Object?> expected = _map(scenario['expected']);
    expect(app.name, expected['name']);
    expect(app.retries, expected['retries']);
    expect(app.tags, expected['tags']);
  });

  for (final Object? item in _list(
    c0ConfigContract.noJsonNoComma['rejected'],
  )) {
    final Map<String, Object?> scenario = _map(item);
    test('C0 rejects ${scenario['name']} list overrides', () {
      final ConfigLoader loader = ConfigLoader(
        base: YamlConfigSource.string(scenario['baseYaml']! as String),
        dartDefines: DartDefineOverrides(
          prefix: scenario['prefix']! as String,
          values: _strings(scenario['defines']),
        ),
        schema: appSchema(),
      );

      expect(loader.load, throwsA(isA<ConfigValidationException>()));
    });
  }

  for (final Object? item in _list(
    c0ConfigContract.caseInsensitiveKeyMatching['variants'],
  )) {
    final Map<String, Object?> variant = _map(item);
    test('C0 matches ${variant['defineKey']} case-insensitively', () async {
      final Map<String, Object?> scenario =
          c0ConfigContract.caseInsensitiveKeyMatching;
      final ConfigBlock<String> displayName = ConfigBlock<String>(
        key: 'appSettings',
        decode: (Map<String, Object?> values) {
          final Object? value = values['displayName'];
          if (value is! String || value.isEmpty) {
            throw const FormatException('displayName must be non-empty');
          }
          return value;
        },
      );
      final ConfigLoader loader = ConfigLoader(
        base: YamlConfigSource.string(scenario['baseYaml']! as String),
        dartDefines: DartDefineOverrides(
          prefix: scenario['prefix']! as String,
          values: <String, String>{
            variant['defineKey']! as String:
                variant['expectedValue']! as String,
          },
        ),
        schema: ConfigSchema(blocks: <ConfigBlockSchema>[displayName]),
      );

      final String actual = (await loader.load()).slice(displayName);

      expect(actual, variant['expectedValue']);
    });
  }

  test('C0 validates only the final merged configuration', () async {
    final Map<String, Object?> scenario =
        c0ConfigContract.layeringAndIndexedList;
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

    final AppBlock app = (await loader.load()).slice(appBlock);

    expect(app.retries, 2);
  });

  test('C0 fails before an invalid final config is exposed', () {
    final Map<String, Object?> scenario = _map(
      c0ConfigContract.finalLayerValidation['invalid'],
    );
    final ConfigLoader loader = ConfigLoader(
      base: YamlConfigSource.string(scenario['baseYaml']! as String),
      dartDefines: DartDefineOverrides(
        prefix: scenario['prefix']! as String,
        values: _strings(scenario['defines']),
      ),
      schema: appSchema(),
    );

    expect(loader.load, throwsA(isA<ConfigValidationException>()));
  });
}

Map<String, Object?> _map(Object? value) =>
    Map<String, Object?>.from(value! as Map<dynamic, dynamic>);

List<Object?> _list(Object? value) =>
    List<Object?>.from(value! as List<dynamic>);

Map<String, String> _strings(Object? value) =>
    Map<String, String>.from(value! as Map<dynamic, dynamic>);
