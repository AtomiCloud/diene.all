import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:diene_config/diene_config.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

import '../support.dart';

/// C0 §3 config-precedence conformance, driven from the FROZEN C0 release.
///
/// The vectors are not written here: they are projected from
/// `contracts/c0/cases/config.json` (release `c0-fixtures-r2`) by
/// `tool/gen_c0_projection.dart` into `test/fixtures/c0/config.json`. This suite
/// reads that projection, so a change to the normative release either flows
/// through or reddens the projection check — it cannot be silently diverged
/// from by editing an assertion in this file.
///
/// Unlike the `diene_core_utils` conformance suite, which projects only the
/// four mechanics that package implements, this one binds ALL FIVE vectors: the
/// `finalLayerValidation` case is the one core-utils leaves to its consumer,
/// and `diene_config` is that consumer.
///
/// The vectors' YAML is fed through the REAL [YamlConfigSource], and the
/// layering through the REAL [ConfigLoader]: this suite proves the shipped
/// loader conforms, not that a test-local reimplementation does.
const String _fixturePath = 'test/fixtures/c0/config.json';
const String _checksumPath = 'test/fixtures/c0/SHA256SUMS';

void main() {
  final String fixtureText = File(_fixturePath).readAsStringSync();
  final Map<String, Object?> fixture =
      (jsonDecode(fixtureText) as Map<Object?, Object?>)
          .cast<String, Object?>();
  final Map<String, Object?> generated =
      (fixture[r'$generated']! as Map<Object?, Object?>)
          .cast<String, Object?>();

  group('C0 release binding', () {
    test(
      'the fixture is the authenticated projection of the pinned release',
      () {
        // Assert
        expect(
          generated['releaseId'],
          c0ConfigContract.provenance.releaseId,
          reason:
              'the projection came from a DIFFERENT release than the '
              'contract this package claims to bind',
        );
        expect(
          generated['releaseDigest'],
          c0ConfigContract.provenance.releaseDigest,
        );
        expect(generated['sourceCase'], c0ConfigContract.provenance.sourceCase);
        expect(generated['domain'], 'config');
        expect(fixture['c0Sections'], c0ConfigContract.provenance.c0Sections);

        // The recorded digest must authenticate the exact bytes just parsed.
        // Comparing the VALUES keeps this from passing on a truncated ledger.
        final String actual = sha256
            .convert(utf8.encode(fixtureText))
            .toString();
        expect(
          File(_checksumPath).readAsStringSync(),
          '$actual  config.json\n',
        );
      },
    );

    test('the release id and contract version agree', () {
      // Assert
      expect(
        c0ConfigContract.provenance.releaseId,
        'c0-fixtures-r${c0ConfigContract.provenance.contractVersion}',
      );
    });

    test('every vector this package claims is present and non-empty', () {
      // Refuse to judge on missing data: a vector that vanished from the
      // projection would otherwise make its group below silently vacuous.
      // Assert
      expect(
        (generated['projectedCases']! as List<Object?>).cast<String>(),
        c0ConfigContract.projectedCases,
      );
      for (final String name in c0ConfigContract.projectedCases) {
        expect(fixture[name], isNotNull, reason: 'vector $name is missing');
        expect(
          (fixture[name]! as Map<Object?, Object?>).isNotEmpty,
          isTrue,
          reason: 'vector $name is empty',
        );
      }
    });

    test('it binds the finalLayerValidation vector core-utils omits', () {
      // This is the ownership boundary in one assertion: validating the merged
      // layer is this package's job, so this vector must be bound HERE.
      // Assert
      expect(c0ConfigContract.projectedCases, contains('finalLayerValidation'));
    });
  });

  group('C0 §3 layering and indexed lists', () {
    test(
      'base, landscape, and define layers apply in precedence order',
      () async {
        // Arrange
        final Map<String, Object?> vector = _vector(
          fixture,
          'layeringAndIndexedList',
        );

        // Act
        final Result<DieneConfig> loaded = await _load(
          vector,
          overlayKey: 'landscapeYaml',
        );

        // Assert
        expect(loaded, isOk, reason: describe(loaded));
        expect(loaded.unwrap().rawSlice('app').unwrap(), vector['expected']);
      },
    );

    test(
      'the development layer sits between the overlay and the defines',
      () async {
        // With the development layer present, its `tags` beats the landscape
        // layer's and is in turn beaten by the indexed defines.
        // Arrange
        final Map<String, Object?> vector = _vector(
          fixture,
          'layeringAndIndexedList',
        );

        // Act
        final Result<DieneConfig> loaded = await _load(
          vector,
          overlayKey: 'landscapeYaml',
          developmentKey: 'developmentYaml',
        );

        // Assert
        expect(loaded, isOk, reason: describe(loaded));
        // The expected tree is unchanged: the defines override the development
        // layer's own name and tags, which is precisely the ordering claim.
        expect(loaded.unwrap().rawSlice('app').unwrap(), vector['expected']);
      },
    );

    test(
      'the development layer DOES win when no define covers its key',
      () async {
        // Without the define layer the development values survive, proving the
        // previous test's result comes from ordering rather than from the
        // development layer being ignored altogether.
        // Arrange
        final Map<String, Object?> vector = _vector(
          fixture,
          'layeringAndIndexedList',
        );

        // Act
        final Result<DieneConfig> loaded = await _load(
          vector,
          overlayKey: 'landscapeYaml',
          developmentKey: 'developmentYaml',
          defines: const <String, String>{},
        );

        // Assert
        expect(loaded, isOk, reason: describe(loaded));
        final Map<String, Object?> app = loaded
            .unwrap()
            .rawSlice('app')
            .unwrap();
        expect(app['name'], 'development');
        expect(app['tags'], <String>['development']);
        expect(app['retries'], 2, reason: 'the landscape layer still applies');
      },
    );

    test('indexed defines build the list that replaces the YAML one', () async {
      // Arrange
      final Map<String, Object?> vector = _vector(
        fixture,
        'layeringAndIndexedList',
      );
      final Map<String, String> defines = _defines(vector);

      // Act
      final Result<DieneConfig> loaded = await _load(
        vector,
        overlayKey: 'landscapeYaml',
      );

      // Assert
      expect(
        defines.keys,
        containsAll(<String>['ACME_APP__TAGS__0', 'ACME_APP__TAGS__1']),
        reason: 'the vector must exercise indexed keys',
      );
      expect(loaded.unwrap().rawSlice('app').unwrap()['tags'], <String>[
        'first',
        'second',
      ]);
    });
  });

  group('C0 §3 blank is unset', () {
    test('a blank define does not erase the base value', () async {
      // Arrange
      final Map<String, Object?> vector = _vector(fixture, 'blankIsUnset');

      // Act
      final Result<DieneConfig> loaded = await _load(vector);

      // Assert
      expect(loaded, isOk, reason: describe(loaded));
      expect(loaded.unwrap().rawSlice('app').unwrap(), vector['expected']);
    });

    test('the blank define layer contributes nothing at all', () async {
      // Arrange
      final Map<String, Object?> vector = _vector(fixture, 'blankIsUnset');
      final DartDefineOverrides overrides = DartDefineOverrides(
        prefix: vector['prefix']! as String,
        values: _defines(vector),
      );

      // Act
      final Result<Object?> layer = overrides.layer();

      // Assert
      expect(layer, isOk, reason: describe(layer));
      expect(layer.unwrap()! as Map<String, Object?>, isEmpty);
    });
  });

  group('C0 §3 case-insensitive key matching', () {
    test('every spelling variant lands on the base layer key', () async {
      // Arrange
      final Map<String, Object?> vector = _vector(
        fixture,
        'caseInsensitiveKeyMatching',
      );
      final List<Object?> variants = vector['variants']! as List<Object?>;
      expect(variants, hasLength(3), reason: 'expected snake, kebab, pascal');

      for (final Object? raw in variants) {
        final Map<String, Object?> variant = (raw! as Map<Object?, Object?>)
            .cast<String, Object?>();
        final String defineKey = variant['defineKey']! as String;
        final String expectedValue = variant['expectedValue']! as String;

        // Act
        final Result<DieneConfig> loaded = await ConfigLoader(
          base: YamlConfigSource.string(vector['baseYaml']! as String),
          dartDefines: DartDefineOverrides(
            prefix: vector['prefix']! as String,
            values: <String, String>{defineKey: expectedValue},
          ),
          schema: ConfigSchema(
            blocks: <ConfigBlockSchema>[
              ConfigBlock<String>(
                key: 'app-settings',
                decode: (Map<String, Object?> values) =>
                    values['displayName']! as String,
              ),
            ],
          ),
        ).load();

        // Assert
        expect(loaded, isOk, reason: '$defineKey: ${describe(loaded)}');
        final DieneConfig config = loaded.unwrap();
        expect(
          config.raw.keys,
          <String>['app-settings'],
          reason: '$defineKey introduced a duplicate root spelling',
        );
        final Map<String, Object?> settings = config
            .rawSlice('app-settings')
            .unwrap();
        expect(
          settings.keys,
          <String>['displayName'],
          reason: "$defineKey did not land on the base layer's spelling",
        );
        expect(settings['displayName'], expectedValue);
      }
    });
  });

  group('C0 §3 no JSON, no comma encoding', () {
    test('neither encoding is ever decoded into a list', () async {
      // Arrange
      final Map<String, Object?> vector = _vector(fixture, 'noJsonNoComma');
      final List<Object?> rejected = vector['rejected']! as List<Object?>;
      expect(rejected, hasLength(2), reason: 'expected JSON and comma cases');

      // The claim under test is about the MERGE — that no list is ever
      // materialised from a JSON or comma string — so the block accepts `tags`
      // whatever its type and the assertion inspects it. A strict decoder would
      // reject the string and the suite would go green on validation instead
      // of on the rule it is meant to bind.
      final ConfigSchema permissive = ConfigSchema(
        blocks: <ConfigBlockSchema>[
          ConfigBlock<Object?>(
            key: 'app',
            decode: (Map<String, Object?> values) => values['tags'],
          ),
        ],
      );

      for (final Object? raw in rejected) {
        final Map<String, Object?> entry = (raw! as Map<Object?, Object?>)
            .cast<String, Object?>();

        // Act
        final Result<DieneConfig> loaded = await ConfigLoader(
          base: YamlConfigSource.string(entry['baseYaml']! as String),
          dartDefines: DartDefineOverrides(
            prefix: entry['prefix']! as String,
            values: _defines(entry),
          ),
          schema: permissive,
        ).load();

        // Assert
        expect(loaded, isOk, reason: '${entry['name']}: ${describe(loaded)}');
        final Object? tags = loaded.unwrap().rawSlice('app').unwrap()['tags'];
        expect(
          tags,
          isA<String>(),
          reason: '${entry['name']} encoding was decoded into a collection',
        );
        expect(tags, _defines(entry).values.single);
      }
    });

    test('a strict decoder still SEES the string, and says so', () async {
      // The complementary half: an application whose block expects a list gets
      // a validation failure naming the type mismatch, rather than a silently
      // decoded list. That is the rule's practical consequence.
      // Arrange
      final Map<String, Object?> vector = _vector(fixture, 'noJsonNoComma');
      final Map<String, Object?> entry =
          ((vector['rejected']! as List<Object?>).first!
                  as Map<Object?, Object?>)
              .cast<String, Object?>();

      // Act
      final Result<DieneConfig> loaded = await ConfigLoader(
        base: YamlConfigSource.string(entry['baseYaml']! as String),
        dartDefines: DartDefineOverrides(
          prefix: entry['prefix']! as String,
          values: _defines(entry),
        ),
        schema: appSchema(),
      ).load();

      // Assert
      expect(loaded, isErr, reason: describe(loaded));
      expect(
        loaded.unwrapErr().data['code'],
        ConfigProblemCode.schemaInvalid.wireId,
      );
    });
  });

  group('C0 §3 final-layer validation', () {
    test('an invalid FINAL tree is rejected', () async {
      // Arrange
      final Map<String, Object?> vector = _vector(
        fixture,
        'finalLayerValidation',
      );
      final Map<String, Object?> invalid =
          (vector['invalid']! as Map<Object?, Object?>).cast<String, Object?>();

      // Act
      final Result<DieneConfig> loaded = await _load(invalid);

      // Assert
      expect(loaded, isErr, reason: describe(loaded));
      final Problem problem = loaded.unwrapErr();
      expect(problem.data['code'], ConfigProblemCode.schemaInvalid.wireId);
      expect(
        (problem.data['errors']! as List<Object?>).join(),
        contains('retries'),
      );
    });

    test('the SAME tree is accepted once a later layer repairs it', () async {
      // Validation is final-layer-only, so the identical base becomes valid
      // when a define fixes it. This is the half of the rule an
      // "invalid input is rejected" test alone cannot prove.
      // Arrange
      final Map<String, Object?> vector = _vector(
        fixture,
        'finalLayerValidation',
      );
      final Map<String, Object?> invalid =
          (vector['invalid']! as Map<Object?, Object?>).cast<String, Object?>();

      // Act
      final Result<DieneConfig> loaded = await _load(
        invalid,
        defines: <String, String>{
          '${invalid['prefix']}APP__RETRIES': '5',
          '${invalid['prefix']}APP__TAGS__0': 'repaired',
        },
      );

      // Assert
      expect(loaded, isOk, reason: describe(loaded));
      final Map<String, Object?> app = loaded.unwrap().rawSlice('app').unwrap();
      expect(app['retries'], 5);
      expect(app['tags'], <String>['repaired']);
    });

    test('validation runs exactly once, on the merged tree', () async {
      // A loader validating each layer would reject the invalid base before
      // the define could repair it — the previous test's Ok is the proof, and
      // this counts the decoder calls to say so directly.
      // Arrange
      final Map<String, Object?> vector = _vector(
        fixture,
        'finalLayerValidation',
      );
      final Map<String, Object?> invalid =
          (vector['invalid']! as Map<Object?, Object?>).cast<String, Object?>();
      int decodeCalls = 0;
      final ConfigBlock<int> countingBlock = ConfigBlock<int>(
        key: 'app',
        decode: (Map<String, Object?> values) {
          decodeCalls += 1;
          return values['retries']! as int;
        },
      );

      // Act
      final Result<DieneConfig> loaded = await ConfigLoader(
        base: YamlConfigSource.string(invalid['baseYaml']! as String),
        overlay: YamlConfigSource.string('app:\n  retries: 1\n'),
        developmentOverride: YamlConfigSource.string('app:\n  retries: 2\n'),
        dartDefines: DartDefineOverrides(
          prefix: invalid['prefix']! as String,
          values: <String, String>{'${invalid['prefix']}APP__RETRIES': '3'},
        ),
        schema: ConfigSchema(blocks: <ConfigBlockSchema>[countingBlock]),
      ).load();

      // Assert
      expect(loaded, isOk, reason: describe(loaded));
      expect(
        decodeCalls,
        1,
        reason: 'four layers were loaded but validation must run ONCE',
      );
      expect(loaded.unwrap().slice(countingBlock), 3);
    });
  });
}

Map<String, Object?> _vector(Map<String, Object?> fixture, String name) =>
    (fixture[name]! as Map<Object?, Object?>).cast<String, Object?>();

Map<String, String> _defines(Map<String, Object?> vector) =>
    (vector['defines']! as Map<Object?, Object?>).cast<String, String>();

/// Runs one fixture vector through the REAL loader.
Future<Result<DieneConfig>> _load(
  Map<String, Object?> vector, {
  String? overlayKey,
  String? developmentKey,
  Map<String, String>? defines,
}) {
  String? layer(String? key) => key == null ? null : vector[key] as String?;

  final String? overlay = layer(overlayKey);
  final String? development = layer(developmentKey);
  return ConfigLoader(
    base: YamlConfigSource.string(
      vector['baseYaml']! as String,
      name: 'base.yaml',
    ),
    overlay: overlay == null
        ? null
        : YamlConfigSource.string(overlay, name: 'overlay.yaml'),
    developmentOverride: development == null
        ? null
        : YamlConfigSource.string(development, name: 'development.yaml'),
    dartDefines: DartDefineOverrides(
      prefix: vector['prefix']! as String,
      values: defines ?? _defines(vector),
    ),
    schema: appSchema(),
  ).load();
}
