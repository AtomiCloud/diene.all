import 'package:diene_config/diene_config.dart';
import 'package:test/test.dart';

void main() {
  group('applyIndexedOverrides', () {
    late Map<String, Object?> base;

    setUp(() {
      base = <String, Object?>{
        'app': <String, Object?>{
          'displayName': 'base',
          'retry_count': 1,
          'enabled': false,
          'ratio': 0.5,
          'tags': <Object?>['old', 'discarded'],
        },
      };
    });

    test('matches key styles and coerces scalar values', () {
      // Arrange.
      final Map<String, String> values = <String, String>{
        'ACME_APP__DISPLAY_NAME': 'override',
        'ACME_APP__RETRY-COUNT': '4',
        'ACME_APP__ENABLED': 'true',
        'ACME_APP__RATIO': '0.75',
      };

      // Act.
      final Map<String, Object?> result = applyIndexedOverrides(
        base,
        values: values,
        prefix: 'ACME_',
      );
      final Map<String, Object?> app = result['app']! as Map<String, Object?>;

      // Assert.
      expect(app['displayName'], 'override');
      expect(app['retry_count'], 4);
      expect(app['enabled'], isTrue);
      expect(app['ratio'], 0.75);
    });

    test('replaces lists from contiguous indexed keys', () {
      // Arrange.
      final Map<String, String> values = <String, String>{
        'ACME_APP__TAGS__1': 'second',
        'ACME_APP__TAGS__0': 'first',
      };

      // Act.
      final Map<String, Object?> result = applyIndexedOverrides(
        base,
        values: values,
        prefix: 'ACME_',
      );

      // Assert.
      expect((result['app']! as Map<String, Object?>)['tags'], <Object?>[
        'first',
        'second',
      ]);
    });

    test('treats blank defines as unset', () {
      // Arrange and act.
      final Map<String, Object?> result = applyIndexedOverrides(
        base,
        values: const <String, String>{'ACME_APP__DISPLAY_NAME': ''},
        prefix: 'ACME_',
      );

      // Assert.
      expect((result['app']! as Map<String, Object?>)['displayName'], 'base');
    });

    test('rejects gaps, unknown keys, scalars, and invalid prefixes', () {
      // Arrange.
      Map<String, Object?> apply(Map<String, String> values) =>
          applyIndexedOverrides(base, values: values, prefix: 'ACME_');

      // Act and assert.
      expect(
        () => apply(const <String, String>{'ACME_APP__TAGS__2': 'gap'}),
        throwsA(isA<ConfigOverrideException>()),
      );
      expect(
        () => apply(const <String, String>{'ACME_APP__TYPO': 'value'}),
        throwsA(isA<ConfigOverrideException>()),
      );
      expect(
        () => apply(const <String, String>{'ACME_APP__ENABLED__CHILD': 'x'}),
        throwsA(isA<ConfigOverrideException>()),
      );
      expect(
        () => apply(const <String, String>{'ACME_APP____NAME': 'x'}),
        throwsA(isA<ConfigOverrideException>()),
      );
      expect(
        () => apply(const <String, String>{'ACME_APP__TAGS__NOPE': 'x'}),
        throwsA(isA<ConfigOverrideException>()),
      );
      expect(
        () => applyIndexedOverrides(base, values: const {}, prefix: ''),
        throwsArgumentError,
      );
    });

    test('builds nested maps inside indexed list overrides', () {
      // Arrange.
      base['servers'] = <Object?>[];
      final Map<String, String> values = <String, String>{
        'ACME_SERVERS__0__HOST': 'one.example.invalid',
        'ACME_SERVERS__0__PORT': '443',
      };

      // Act.
      final Map<String, Object?> result = applyIndexedOverrides(
        base,
        values: values,
        prefix: 'ACME_',
      );

      // Assert.
      expect(result['servers'], <Object?>[
        <String, Object?>{'host': 'one.example.invalid', 'port': 443},
      ]);
    });

    test('does not parse JSON or comma-separated list values', () {
      // Arrange.
      final Map<String, String> values = <String, String>{
        'ACME_APP__DISPLAY_NAME': '["not", "a", "list"]',
      };

      // Act.
      final Map<String, Object?> result = applyIndexedOverrides(
        base,
        values: values,
        prefix: 'ACME_',
      );

      // Assert.
      expect(
        (result['app']! as Map<String, Object?>)['displayName'],
        '["not", "a", "list"]',
      );
    });
  });

  test('DartDefineOverrides requires an app-owned prefix', () {
    // Arrange, act, and assert.
    expect(
      () => DartDefineOverrides(prefix: '', values: const {}),
      throwsArgumentError,
    );
  });
}
