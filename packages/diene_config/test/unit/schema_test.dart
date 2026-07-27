import 'package:diene_config/diene_config.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

import '../support.dart';

/// A second block type, so composition across DIFFERENT typed blocks is
/// exercised rather than assumed.
final class ApiSettings {
  const ApiSettings(this.baseUrl);

  final String baseUrl;

  @override
  bool operator ==(Object other) =>
      other is ApiSettings && other.baseUrl == baseUrl;

  @override
  int get hashCode => baseUrl.hashCode;

  @override
  String toString() => 'ApiSettings($baseUrl)';
}

final ConfigBlock<ApiSettings> apiBlock = ConfigBlock<ApiSettings>(
  key: 'api',
  decode: (Map<String, Object?> values) =>
      ApiSettings(values['baseUrl']! as String),
);

final ConfigBlock<ApiSettings> optionalApiBlock = ConfigBlock<ApiSettings>(
  key: 'api',
  required: false,
  decode: (Map<String, Object?> values) =>
      ApiSettings(values['baseUrl']! as String),
);

Map<String, Object?> validApp() => <String, Object?>{
  'app': <String, Object?>{
    'name': 'service',
    'retries': 2,
    'tags': <Object?>['alpha'],
  },
};

List<String> errorsOf(Problem problem) =>
    (problem.data['errors']! as List<Object?>)
        .map((Object? error) => '$error')
        .toList(growable: false);

void main() {
  group('ConfigSchema construction', () {
    test('rejects an empty block key as programmer misuse', () {
      // A block list is source code, not input, so this throws rather than
      // returning a failure value.
      expect(
        () => ConfigSchema(
          blocks: <ConfigBlockSchema>[
            ConfigBlock<int>(key: '', decode: (_) => 0),
          ],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test(r'rejects the reserved $schema key', () {
      expect(
        () => ConfigSchema(
          blocks: <ConfigBlockSchema>[
            ConfigBlock<int>(key: r'$schema', decode: (_) => 0),
          ],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects two blocks whose keys canonicalise together', () {
      // `app-settings` and `appSettings` are the SAME key under C0 §3 matching,
      // so composing both is ambiguous by construction.
      expect(
        () => ConfigSchema(
          blocks: <ConfigBlockSchema>[
            ConfigBlock<int>(key: 'app-settings', decode: (_) => 0),
            ConfigBlock<int>(key: 'appSettings', decode: (_) => 1),
          ],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('exposes its composed blocks, unmodifiably', () {
      // Arrange
      final ConfigSchema schema = appSchema();

      // Assert
      expect(schema.blocks, hasLength(1));
      expect(schema.blocks.single.key, 'app');
      expect(schema.rejectUnknownBlocks, isTrue);
      expect(() => schema.blocks.clear(), throwsUnsupportedError);
    });

    test('accepts an empty block list against an empty configuration', () {
      // Arrange
      final ConfigSchema schema = ConfigSchema(
        blocks: const <ConfigBlockSchema>[],
      );

      // Act
      final Result<DieneConfig> validated = schema.validate(
        <String, Object?>{},
      );

      // Assert
      expect(validated, isOk, reason: describe(validated));
      expect(validated.unwrap().raw, isEmpty);
    });
  });

  group('ConfigSchema.validate', () {
    test('decodes a valid configuration into a typed slice', () {
      // Act
      final Result<DieneConfig> validated = appSchema().validate(validApp());

      // Assert
      expect(validated, isOk, reason: describe(validated));
      expect(
        validated.unwrap().slice(appBlock),
        const AppSettings(name: 'service', retries: 2, tags: <String>['alpha']),
      );
    });

    test('matches a block key case- and separator-insensitively', () {
      // Arrange
      final ConfigSchema schema = ConfigSchema(
        blocks: <ConfigBlockSchema>[
          ConfigBlock<String>(
            key: 'app-settings',
            decode: (Map<String, Object?> values) =>
                values['displayName']! as String,
          ),
        ],
      );

      // Act
      final Result<DieneConfig> validated = schema.validate(<String, Object?>{
        'AppSettings': <String, Object?>{'displayName': 'matched'},
      });

      // Assert
      expect(validated, isOk, reason: describe(validated));
      expect(
        validated.unwrap().slice(
          ConfigBlock<String>(
            key: 'app-settings',
            decode: (Map<String, Object?> values) =>
                values['displayName']! as String,
          ),
        ),
        'matched',
      );
    });

    test(r'ignores the reserved $schema root key', () {
      // A YAML authored against a JSON-schema-aware editor carries it.
      // Arrange
      final Map<String, Object?> values = validApp()
        ..[r'$schema'] = 'https://example.test/config.json';

      // Act
      final Result<DieneConfig> validated = appSchema().validate(values);

      // Assert
      expect(validated, isOk, reason: describe(validated));
    });

    test('reports a missing required block', () {
      // Act
      final Result<DieneConfig> validated = appSchema().validate(
        <String, Object?>{},
      );

      // Assert
      expect(validated, isErr, reason: describe(validated));
      final Problem problem = validated.unwrapErr();
      expect(problem.data['code'], ConfigProblemCode.schemaInvalid.wireId);
      expect(problem.status, 422);
      expect(errorsOf(problem), <String>['app: required block is missing']);
    });

    test('accepts an absent optional block', () {
      // Arrange
      final ConfigSchema schema = ConfigSchema(
        blocks: <ConfigBlockSchema>[appBlock, optionalApiBlock],
      );

      // Act
      final Result<DieneConfig> validated = schema.validate(validApp());

      // Assert
      expect(validated, isOk, reason: describe(validated));
      final DieneConfig config = validated.unwrap();
      expect(config.hasSlice(optionalApiBlock), isFalse);
      expect(config.optionalSlice(optionalApiBlock).isNone, isTrue);
    });

    test('decodes an optional block that IS present', () {
      // Arrange
      final ConfigSchema schema = ConfigSchema(
        blocks: <ConfigBlockSchema>[appBlock, optionalApiBlock],
      );
      final Map<String, Object?> values = validApp()
        ..['api'] = <String, Object?>{'baseUrl': 'https://api.test'};

      // Act
      final DieneConfig config = schema.validate(values).unwrap();

      // Assert
      expect(config.hasSlice(optionalApiBlock), isTrue);
      expect(
        config.optionalSlice(optionalApiBlock).unwrap(),
        const ApiSettings('https://api.test'),
      );
    });

    test('reports a block whose value is not a map', () {
      // Act
      final Result<DieneConfig> validated = appSchema().validate(
        <String, Object?>{'app': 'not a map'},
      );

      // Assert
      expect(errorsOf(validated.unwrapErr()), <String>[
        'app: block must be a map',
      ]);
    });

    test('reports a block whose value is a list', () {
      // Act
      final Result<DieneConfig> validated = appSchema().validate(
        <String, Object?>{
          'app': <Object?>['nope'],
        },
      );

      // Assert
      expect(errorsOf(validated.unwrapErr()), <String>[
        'app: block must be a map',
      ]);
    });

    test('folds a throwing decoder into the aggregate problem', () {
      // Act
      final Result<DieneConfig> validated = appSchema().validate(
        <String, Object?>{
          'app': <String, Object?>{'name': '', 'retries': 1},
        },
      );

      // Assert
      final List<String> errors = errorsOf(validated.unwrapErr());
      expect(errors, hasLength(1));
      expect(errors.single, startsWith('app: '));
      expect(errors.single, contains('non-empty string'));
    });

    test('rejects an unknown root key by default', () {
      // Arrange
      final Map<String, Object?> values = validApp()
        ..['aap'] = <String, Object?>{'typo': true};

      // Act
      final Result<DieneConfig> validated = appSchema().validate(values);

      // Assert
      expect(errorsOf(validated.unwrapErr()), <String>[
        'aap: no composed block schema',
      ]);
    });

    test('tolerates an unknown root key when told to', () {
      // Arrange
      final Map<String, Object?> values = validApp()
        ..['extra'] = <String, Object?>{'ok': true};

      // Act
      final Result<DieneConfig> validated = appSchema(
        rejectUnknownBlocks: false,
      ).validate(values);

      // Assert
      expect(validated, isOk, reason: describe(validated));
      expect(validated.unwrap().raw.containsKey('extra'), isTrue);
    });

    test('reports two root keys that collide under canonicalisation', () {
      // Act
      final Result<DieneConfig> validated = appSchema().validate(
        <String, Object?>{
          'app': <String, Object?>{'name': 'a', 'retries': 0},
          'A_P_P': <String, Object?>{'name': 'b', 'retries': 0},
        },
      );

      // Assert
      final List<String> errors = errorsOf(validated.unwrapErr());
      expect(errors.first, 'root keys app and A_P_P collide');
    });

    test('reports EVERY problem in one pass, not just the first', () {
      // One pass that stops at the first error makes a misconfiguration take
      // as many deploys to fix as it has mistakes.
      // Arrange
      final ConfigSchema schema = ConfigSchema(
        blocks: <ConfigBlockSchema>[appBlock, apiBlock],
      );

      // Act
      final Result<DieneConfig> validated = schema.validate(<String, Object?>{
        'app': <String, Object?>{'name': 'service', 'retries': -1},
        'unknown': <String, Object?>{},
      });

      // Assert
      final List<String> errors = errorsOf(validated.unwrapErr());
      expect(errors, hasLength(3));
      expect(errors, contains('api: required block is missing'));
      expect(errors, contains('unknown: no composed block schema'));
      expect(errors.any((String e) => e.startsWith('app: ')), isTrue);
    });

    test('carries an unmodifiable error list', () {
      // Act
      final Problem problem = appSchema()
          .validate(<String, Object?>{})
          .unwrapErr();

      // Assert
      expect(
        () => (problem.data['errors']! as List<Object?>).clear(),
        throwsUnsupportedError,
      );
    });
  });

  group('DieneConfig', () {
    test('exposes a deeply immutable raw tree', () {
      // Arrange
      final DieneConfig config = appSchema().validate(validApp()).unwrap();

      // Assert
      expect(() => config.raw['app'] = null, throwsUnsupportedError);
      final Map<String, Object?> app =
          config.raw['app']! as Map<String, Object?>;
      expect(() => app['name'] = 'mutated', throwsUnsupportedError);
      expect(
        () => (app['tags']! as List<Object?>).add('mutated'),
        throwsUnsupportedError,
      );
    });

    test('rawSlice returns an untyped view, matched insensitively', () {
      // Arrange
      final DieneConfig config = appSchema().validate(validApp()).unwrap();

      // Act
      final Result<Map<String, Object?>> slice = config.rawSlice('A-P-P');

      // Assert
      expect(slice, isOk, reason: describe(slice));
      expect(slice.unwrap()['name'], 'service');
    });

    test('rawSlice reports a block that was not loaded', () {
      // Arrange
      final DieneConfig config = appSchema().validate(validApp()).unwrap();

      // Act
      final Result<Map<String, Object?>> slice = config.rawSlice('absent');

      // Assert
      expect(slice, isErr, reason: describe(slice));
      expect(
        slice.unwrapErr().data['code'],
        ConfigProblemCode.schemaInvalid.wireId,
      );
      expect(slice.unwrapErr().data['block'], 'absent');
    });

    test('rawSlice reports a root key that is not a map', () {
      // Arrange
      final DieneConfig config = appSchema(
        rejectUnknownBlocks: false,
      ).validate(validApp()..['scalar'] = 7).unwrap();

      // Act
      final Result<Map<String, Object?>> slice = config.rawSlice('scalar');

      // Assert
      expect(slice, isErr, reason: describe(slice));
      expect(slice.unwrapErr().title, contains('is not a map'));
    });

    test('slice throws for a block that was never composed', () {
      // Asking for a slice that structurally cannot exist is programmer
      // misuse, so it throws rather than returning a failure value.
      // Arrange
      final DieneConfig config = appSchema().validate(validApp()).unwrap();

      // Assert
      expect(() => config.slice(apiBlock), throwsStateError);
    });

    test('slice throws for an absent optional block', () {
      // Arrange
      final DieneConfig config = ConfigSchema(
        blocks: <ConfigBlockSchema>[appBlock, optionalApiBlock],
      ).validate(validApp()).unwrap();

      // Assert
      expect(() => config.slice(optionalApiBlock), throwsStateError);
    });

    test('stableProjection sorts keys at every depth', () {
      // Arrange
      final DieneConfig config = appSchema(rejectUnknownBlocks: false).validate(
        <String, Object?>{
          'zeta': <String, Object?>{'b': 1, 'a': 2},
          'app': <String, Object?>{'name': 'service', 'retries': 0},
        },
      ).unwrap();

      // Act
      final Result<Object?> projected = config.stableProjection();

      // Assert
      expect(projected, isOk, reason: describe(projected));
      final Map<String, Object?> tree =
          projected.unwrap()! as Map<String, Object?>;
      expect(tree.keys, <String>['app', 'zeta']);
      expect((tree['zeta']! as Map<String, Object?>).keys, <String>['a', 'b']);
    });
  });

  group('ConfigBlock', () {
    test('decodeUntyped erases the static type without changing the value', () {
      // Act
      final Object? decoded = appBlock.decodeUntyped(<String, Object?>{
        'name': 'erased',
        'retries': 3,
      });

      // Assert
      expect(
        decoded,
        const AppSettings(name: 'erased', retries: 3, tags: <String>[]),
      );
    });

    test('is required by default', () {
      expect(appBlock.required, isTrue);
      expect(optionalApiBlock.required, isFalse);
    });
  });
}
