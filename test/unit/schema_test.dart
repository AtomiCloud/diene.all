import 'package:diene_config/diene_config.dart';
import 'package:test/test.dart';

import '../support.dart';

void main() {
  group('ConfigSchema', () {
    test('composes typed engine blocks and serves immutable slices', () {
      // Arrange.
      final ConfigSchema schema = appSchema();
      final Map<String, Object?> raw = <String, Object?>{
        r'$schema': 'schema.json',
        'App': <String, Object?>{
          'name': 'service',
          'retries': 2,
          'tags': <Object?>['mobile'],
        },
      };

      // Act.
      final DieneConfig config = schema.validate(raw);

      // Assert.
      expect(config.slice(appBlock).name, 'service');
      expect(config.rawSlice('app')['retries'], 2);
      expect(
        () => config.rawSlice('app')['retries'] = 3,
        throwsUnsupportedError,
      );
    });

    test('aggregates missing, invalid, and unknown block errors', () {
      // Arrange.
      final ConfigSchema schema = ConfigSchema(
        blocks: <ConfigBlockSchema>[
          appBlock,
          ConfigBlock<String>(
            key: 'auth',
            decode: (Map<String, Object?> value) => value['issuer']! as String,
          ),
        ],
      );
      final Map<String, Object?> raw = <String, Object?>{
        'app': <String, Object?>{
          'name': '',
          'retries': -1,
          'tags': <Object?>[],
        },
        'extra': <String, Object?>{},
      };

      // Act.
      ConfigValidationException? failure;
      try {
        schema.validate(raw);
      } on ConfigValidationException catch (error) {
        failure = error;
      }

      // Assert.
      expect(failure, isNotNull);
      expect(failure!.errors, hasLength(3));
      expect(failure.toString(), contains('auth: required block is missing'));
      expect(failure.toString(), contains('extra: no composed block schema'));
    });

    test('rejects duplicate schema keys after canonical normalization', () {
      // Arrange, act, and assert.
      expect(
        () => ConfigSchema(
          blocks: <ConfigBlockSchema>[
            ConfigBlock<Object?>(key: 'api-client', decode: (_) => null),
            ConfigBlock<Object?>(key: 'API_CLIENT', decode: (_) => null),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('rejects invalid block keys and colliding root keys', () {
      // Arrange, act, and assert.
      expect(
        () => ConfigSchema(
          blocks: <ConfigBlockSchema>[
            ConfigBlock<Object?>(key: r'$schema', decode: (_) => null),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => appSchema().validate(<String, Object?>{
          'app': <String, Object?>{
            'name': 'first',
            'retries': 1,
            'tags': <Object?>[],
          },
          'APP': <String, Object?>{
            'name': 'second',
            'retries': 1,
            'tags': <Object?>[],
          },
        }),
        throwsA(isA<ConfigValidationException>()),
      );
    });

    test('rejects scalar blocks and missing raw slices', () {
      // Arrange.
      final ConfigSchema permissive = ConfigSchema(
        blocks: <ConfigBlockSchema>[],
        rejectUnknownBlocks: false,
      );

      // Act and assert.
      expect(
        () => appSchema().validate(<String, Object?>{'app': 'scalar'}),
        throwsA(isA<ConfigValidationException>()),
      );
      final DieneConfig scalar = permissive.validate(<String, Object?>{
        'extension': 'scalar',
      });
      expect(() => scalar.rawSlice('missing'), throwsStateError);
      expect(() => scalar.rawSlice('extension'), throwsStateError);
    });

    test('supports optional blocks and explicit unknown-block opt-out', () {
      // Arrange.
      final ConfigBlock<String> optional = ConfigBlock<String>(
        key: 'optional',
        required: false,
        decode: (Map<String, Object?> value) => value['value']! as String,
      );
      final ConfigSchema schema = ConfigSchema(
        blocks: <ConfigBlockSchema>[appBlock, optional],
        rejectUnknownBlocks: false,
      );

      // Act.
      final DieneConfig config = schema.validate(<String, Object?>{
        'app': <String, Object?>{
          'name': 'service',
          'retries': 1,
          'tags': <Object?>[],
        },
        'extension': <String, Object?>{},
      });

      // Assert.
      expect(config.slice(appBlock).name, 'service');
      expect(() => config.slice(optional), throwsStateError);
    });
  });
}
