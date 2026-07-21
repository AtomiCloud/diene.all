import 'package:diene_core_utils/diene_core_utils.dart';
import 'package:test/test.dart';

void main() {
  group('slugify', () {
    final Map<String, String> fixtures = <String, String>{
      'Hello World': 'hello-world',
      '  Trim Me  ': 'trim-me',
      'Multiple   Spaces': 'multiple-spaces',
      'Symbols!@#Here': 'symbols-here',
      'already-slugged': 'already-slugged',
      'mañana': 'manana',
      'résumé café': 'resume-cafe',
      '!!! ???': '',
    };

    for (final MapEntry<String, String> fixture in fixtures.entries) {
      test('normalizes ${fixture.key}', () {
        // Arrange
        final String input = fixture.key;

        // Act
        final String actual = slugify(input);

        // Assert
        expect(actual, fixture.value);
      });
    }
  });

  group('namespacedKey', () {
    test('joins normalized components without throwing', () {
      // Arrange
      const String namespace = 'Dart Core Utils';
      const String key = 'Sample Key';

      // Act
      final NamespacedKeyResult actual = namespacedKey(namespace, key);

      // Assert
      expect(actual, const ValidNamespacedKey('dart-core-utils:sample-key'));
      expect(actual.isValid, isTrue);
      expect(actual.hashCode, 'dart-core-utils:sample-key'.hashCode);
      expect(
        actual.match(valid: (String value) => value, invalid: (_) => 'bad'),
        'dart-core-utils:sample-key',
      );
    });

    test('returns namespace validation as data', () {
      // Arrange
      const String namespace = '!!!';

      // Act
      final NamespacedKeyResult actual = namespacedKey(namespace, 'key');

      // Assert
      expect(
        actual,
        const InvalidNamespacedKey(
          NamespacedKeyValidationError(
            field: NamespacedKeyField.namespace,
            reason: 'must not be empty',
          ),
        ),
      );
      expect(actual.isValid, isFalse);
      expect(
        actual.hashCode,
        const NamespacedKeyValidationError(
          field: NamespacedKeyField.namespace,
          reason: 'must not be empty',
        ).hashCode,
      );
      expect(
        actual.match(valid: (_) => 'bad', invalid: (error) => error.toString()),
        'namespace must not be empty',
      );
    });

    test('returns key validation as data', () {
      // Arrange
      const String key = '???';

      // Act
      final NamespacedKeyResult actual = namespacedKey('namespace', key);

      // Assert
      expect(
        actual,
        const InvalidNamespacedKey(
          NamespacedKeyValidationError(
            field: NamespacedKeyField.key,
            reason: 'must not be empty',
          ),
        ),
      );
    });
  });
}
