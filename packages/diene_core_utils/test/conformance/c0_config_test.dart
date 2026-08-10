import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:diene_core_utils/diene_core_utils.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

/// C0 §3 config-precedence conformance, driven from the FROZEN C0 release.
///
/// The vectors are not written here: they are projected from
/// `contracts/c0/cases/config.json` (release `c0-fixtures-r2`) by
/// `tool/gen_c0_projection.dart` into `test/fixtures/c0/config.json`. This suite
/// reads that projection, so a change to the normative release either flows
/// through or reddens the projection check — it cannot be silently diverged from
/// by editing an assertion in this file.
///
/// The YAML layers in the fixture are read with a deliberately tiny reader
/// defined at the bottom of this file rather than a YAML package, because
/// `diene_core_utils` ships no parser: what is under test is the MERGE and
/// PRECEDENCE semantics, not YAML lexing.
const String _fixturePath = 'test/fixtures/c0/config.json';
const String _checksumPath = 'test/fixtures/c0/SHA256SUMS';

void main() {
  final File fixtureFile = File(_fixturePath);
  final String fixtureText = fixtureFile.readAsStringSync();
  final Map<String, Object?> fixture =
      (jsonDecode(fixtureText) as Map<Object?, Object?>)
          .cast<String, Object?>();

  group('C0 release binding', () {
    test(
      'fixture is the authenticated projection of release c0-fixtures-r2',
      () {
        final Map<String, Object?> generated =
            (fixture[r'$generated']! as Map<Object?, Object?>)
                .cast<String, Object?>();
        expect(generated['releaseId'], 'c0-fixtures-r2');
        expect(generated['domain'], 'config');
        expect(generated['sourceCase'], 'contracts/c0/cases/config.json');
        expect(
          generated['releaseDigest'],
          '0e64439c681a22fb4f02285c082ed8ffb7b465e732fde4e49757e9e3c9a5783e',
        );
        expect(fixture['c0Sections'], <String>['§3 Config precedence']);

        // The recorded digest must authenticate the exact bytes just parsed.
        // Comparing the VALUES (not just "a line matched") keeps this from
        // passing on an empty or truncated ledger.
        final String actual = sha256
            .convert(utf8.encode(fixtureText))
            .toString();
        final String ledger = File(_checksumPath).readAsStringSync();
        expect(ledger, '$actual  config.json\n');
      },
    );

    test('every projected vector is present and non-empty', () {
      final List<String> projected =
          (fixture[r'$generated']! as Map<Object?, Object?>)['projectedCases']!
              .let<List<String>>(
                (Object? v) => (v! as List<Object?>).cast<String>(),
              );
      expect(projected, <String>[
        'blankIsUnset',
        'caseInsensitiveKeyMatching',
        'layeringAndIndexedList',
        'noJsonNoComma',
      ]);
      // Refuse to judge on missing data: a vector that vanished from the
      // projection would otherwise make its group below silently vacuous.
      for (final String name in projected) {
        expect(fixture[name], isNotNull, reason: 'vector $name is missing');
        expect(
          (fixture[name]! as Map<Object?, Object?>).isNotEmpty,
          isTrue,
          reason: 'vector $name is empty',
        );
      }
    });
  });

  group('C0 §3 layering and indexed lists', () {
    test('base, landscape, and define layers apply in precedence order', () {
      final Map<String, Object?> vector = _vector(
        fixture,
        'layeringAndIndexedList',
      );
      final String prefix = vector['prefix']! as String;

      final JsonObject base = _readTinyYaml(vector['baseYaml']! as String);
      final JsonObject landscape = _readTinyYaml(
        vector['landscapeYaml']! as String,
      );
      final Result<JsonObject> defines = environmentToNestedMap(
        _defines(vector),
        prefix: prefix,
      );

      expect(defines.isOk, isTrue, reason: 'defines: ${_describe(defines)}');
      final JsonObject merged = deepMergeAll(<JsonObject>[
        base,
        landscape,
        defines.unwrap(),
      ]);

      expect(merged['app'], vector['expected']);
    });

    test('the development layer sits between base and landscape', () {
      final Map<String, Object?> vector = _vector(
        fixture,
        'layeringAndIndexedList',
      );
      final JsonObject base = _readTinyYaml(vector['baseYaml']! as String);
      final JsonObject development = _readTinyYaml(
        vector['developmentYaml']! as String,
      );

      final JsonObject merged = deepMergeAll(<JsonObject>[base, development]);
      final JsonObject app = merged['app']! as JsonObject;
      expect(app['name'], 'development');
      expect(app['tags'], <String>['development']);
      // The base's own key survives a layer that does not mention it.
      expect(app['retries'], -1);
    });
  });

  group('C0 §3 blank is unset', () {
    test('a blank define does not erase the base value', () {
      final Map<String, Object?> vector = _vector(fixture, 'blankIsUnset');
      final JsonObject base = _readTinyYaml(vector['baseYaml']! as String);
      final Result<JsonObject> defines = environmentToNestedMap(
        _defines(vector),
        prefix: vector['prefix']! as String,
      );

      expect(defines.isOk, isTrue, reason: _describe(defines));
      // A blank value is UNSET, so the define layer contributes NOTHING at all.
      expect(defines.unwrap(), isEmpty);
      expect(
        deepMergeAll(<JsonObject>[base, defines.unwrap()])['app'],
        vector['expected'],
      );
      // And the scalar coercion agrees at the unit level.
      expect(coerceEnvironmentScalar(''), isNull);
    });
  });

  group('C0 §3 case-insensitive key matching', () {
    test('every spelling variant lands on the base layer key', () {
      final Map<String, Object?> vector = _vector(
        fixture,
        'caseInsensitiveKeyMatching',
      );
      final String prefix = vector['prefix']! as String;
      final JsonObject base = _readTinyYaml(vector['baseYaml']! as String);
      final List<Object?> variants = vector['variants']! as List<Object?>;

      expect(variants, hasLength(3), reason: 'expected snake, kebab, pascal');
      for (final Object? raw in variants) {
        final Map<String, Object?> variant = (raw! as Map<Object?, Object?>)
            .cast<String, Object?>();
        final String defineKey = variant['defineKey']! as String;
        final String expectedValue = variant['expectedValue']! as String;

        final Result<JsonObject> defines = environmentToNestedMap(
          <String, String>{defineKey: expectedValue},
          prefix: prefix,
        );
        expect(
          defines.isOk,
          isTrue,
          reason: '$defineKey: ${_describe(defines)}',
        );

        final JsonObject merged = deepMergeAll(<JsonObject>[
          base,
          defines.unwrap(),
        ]);
        // The BASE layer's spelling wins as the output key; only the value moves.
        expect(merged.keys, <String>[
          'app-settings',
        ], reason: '$defineKey introduced a duplicate spelling');
        final JsonObject settings = merged['app-settings']! as JsonObject;
        expect(settings.keys, <String>['displayName']);
        expect(settings['displayName'], expectedValue);
      }
    });
  });

  group('C0 §3 no JSON, no comma encoding', () {
    test('neither encoding is ever decoded into a list', () {
      final Map<String, Object?> vector = _vector(fixture, 'noJsonNoComma');
      final List<Object?> rejected = vector['rejected']! as List<Object?>;
      expect(rejected, hasLength(2), reason: 'expected JSON and comma cases');

      for (final Object? raw in rejected) {
        final Map<String, Object?> entry = (raw! as Map<Object?, Object?>)
            .cast<String, Object?>();
        final Result<JsonObject> defines = environmentToNestedMap(
          _defines(entry),
          prefix: entry['prefix']! as String,
        );
        expect(defines.isOk, isTrue, reason: _describe(defines));

        final JsonObject app = defines.unwrap()['app']! as JsonObject;
        // The value stays the STRING it was: no list appears.
        expect(
          app['tags'],
          isA<String>(),
          reason: '${entry['name']} encoding was decoded into a collection',
        );
        expect(app['tags'], _defines(entry).values.single);
      }
    });
  });
}

Map<String, Object?> _vector(Map<String, Object?> fixture, String name) =>
    (fixture[name]! as Map<Object?, Object?>).cast<String, Object?>();

Map<String, String> _defines(Map<String, Object?> vector) =>
    (vector['defines']! as Map<Object?, Object?>).cast<String, String>();

String _describe(Result<Object?> result) => result.match(
  ok: (Object? value) => 'ok($value)',
  err: (Problem problem) => 'err(${problem.title}: ${problem.detail})',
);

/// A deliberately minimal reader for the two-level, block-style YAML the C0
/// config vectors use (`key:` maps, scalars, and `[a, b]` inline sequences).
///
/// `diene_core_utils` ships no YAML parser and must not grow one: the contract
/// under test is the merge, not the lexer. Keeping the reader here — in the
/// test, ~30 lines, handling exactly the fixture's grammar — is what lets the
/// package stay parser-free while still binding the normative vectors.
JsonObject _readTinyYaml(String source) {
  final JsonObject root = <String, Object?>{};
  JsonObject cursor = root;
  for (final String raw in source.split('\n')) {
    if (raw.trim().isEmpty) {
      continue;
    }
    final int indent = raw.length - raw.trimLeft().length;
    final String line = raw.trim();
    final int colon = line.indexOf(':');
    final String key = line.substring(0, colon);
    final String value = line.substring(colon + 1).trim();

    if (indent == 0) {
      if (value.isEmpty) {
        final JsonObject child = <String, Object?>{};
        root[key] = child;
        cursor = child;
      } else {
        root[key] = _readTinyScalar(value);
        cursor = root;
      }
      continue;
    }
    cursor[key] = _readTinyScalar(value);
  }
  return root;
}

Object? _readTinyScalar(String value) {
  if (value.startsWith('[') && value.endsWith(']')) {
    final String inner = value.substring(1, value.length - 1).trim();
    if (inner.isEmpty) {
      return <Object?>[];
    }
    return <Object?>[
      for (final String item in inner.split(',')) _readTinyScalar(item.trim()),
    ];
  }
  final int? asInt = int.tryParse(value);
  return asInt ?? value;
}

extension _Let<T> on T {
  R let<R>(R Function(T value) mapper) => mapper(this);
}
