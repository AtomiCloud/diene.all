import 'package:diene_core_utils/diene_core_utils.dart';
import 'package:test/test.dart';

void main() {
  group('deepMerge', () {
    test('merges nested maps and replaces lists and scalars', () {
      // Arrange
      final JsonObject base = <String, Object?>{
        'auth': <String, Object?>{
          'clientId': 'base',
          'scopes': <Object?>['openid'],
        },
        'enabled': false,
      };
      final JsonObject overlay = <String, Object?>{
        'AUTH': <String, Object?>{
          'client_id': 'overlay',
          'scopes': <Object?>['openid', 'offline_access'],
        },
        'enabled': true,
      };

      // Act
      final JsonObject actual = deepMerge(base, overlay);

      // Assert
      expect(actual, <String, Object?>{
        'auth': <String, Object?>{
          'clientId': 'overlay',
          'scopes': <Object?>['openid', 'offline_access'],
        },
        'enabled': true,
      });
      expect(base['enabled'], isFalse);
    });

    test('merges layers in declaration order and deep clones values', () {
      // Arrange
      final List<Object?> sourceList = <Object?>['base'];
      final List<JsonObject> layers = <JsonObject>[
        <String, Object?>{'list': sourceList, 'value': 1},
        <String, Object?>{'value': 2},
      ];

      // Act
      final JsonObject actual = deepMergeAll(layers);
      sourceList.add('mutated');

      // Assert
      expect(actual, <String, Object?>{
        'list': <Object?>['base'],
        'value': 2,
      });
      expect(configKeysMatch('ErrorPortal', 'error_portal'), isTrue);
      expect(configKeysMatch('client-id', 'clientId'), isTrue);
      expect(configKeysMatch('one', 'two'), isFalse);
    });
  });

  group('environment coercion', () {
    test('coerces scalars and materializes indexed lists', () {
      // Arrange
      final Map<String, String> environment = <String, String>{
        'ATOMI_AUTH__ENABLED': 'true',
        'ATOMI_AUTH__RETRIES': '3',
        'ATOMI_AUTH__RATIO': '0.25',
        'ATOMI_AUTH__SCOPES__0': 'openid',
        'ATOMI_AUTH__SCOPES__1': 'offline_access',
        'ATOMI_AUTH__EMPTY': '',
        'OTHER_KEY': 'ignored',
      };

      // Act
      final JsonObject actual = environmentToNestedMap(
        environment,
        prefix: 'ATOMI_',
      );

      // Assert
      expect(actual, <String, Object?>{
        'auth': <String, Object?>{
          'enabled': true,
          'ratio': 0.25,
          'retries': 3,
          'scopes': <Object?>['openid', 'offline_access'],
        },
      });
    });

    test('keeps unsafe integers and encoded list-looking strings as strings',
        () {
      // Arrange
      const String unsafeInteger = '9007199254740992';
      const String encodedList = 'one,two';

      // Act
      final Object? unsafe = coerceEnvironmentScalar(unsafeInteger);
      final Object? list = coerceEnvironmentScalar(encodedList);

      // Assert
      expect(unsafe, unsafeInteger);
      expect(list, encodedList);
      expect(coerceEnvironmentScalar('false'), isFalse);
      expect(coerceEnvironmentScalar(''), isNull);
      expect(coerceEnvironmentScalar('1e3'), 1000.0);
    });

    test('is config-numeric coercion, not a C0 money/wire-decimal codec', () {
      // Arrange — a config decimal (ratio/timeout) versus a value that must
      // stay exact. C0 §1: money/exact decimals are decimal STRINGS, never
      // floats; only config numerics are coerced here.
      const String configRatio = '0.25';
      const String exactDecimal = '9007199254740993.0001';
      const String bigInteger = '9007199254740993';

      // Act
      final Object? ratio = coerceEnvironmentScalar(configRatio);
      final Object? coercedDecimal = coerceEnvironmentScalar(exactDecimal);
      final Object? preservedInteger = coerceEnvironmentScalar(bigInteger);

      // Assert — config decimals become doubles (ergonomic, lossy)...
      expect(ratio, isA<double>());
      expect(ratio, 0.25);
      // ...and coercing an exact decimal through this config path is lossy,
      // which is exactly why the C0 money/wire boundary keeps it a string.
      expect(coercedDecimal, isA<double>());
      expect((coercedDecimal! as double).toString(), isNot(exactDecimal));
      // Integers past the IEEE-754 safe range are preserved as strings on the
      // same precision boundary money decimals rely on.
      expect(preservedInteger, isA<String>());
      expect(preservedInteger, bigInteger);
    });

    test('rejects malformed, colliding, mixed, and sparse paths', () {
      // Arrange
      final List<Map<String, String>> invalidCases = <Map<String, String>>[
        <String, String>{'ATOMI_': 'value'},
        <String, String>{'ATOMI_A____B': 'value'},
        <String, String>{'ATOMI_A': 'value', 'ATOMI_A__B': 'value'},
        <String, String>{'ATOMI_A': 'value', 'ATOMI_a': 'value'},
        <String, String>{'ATOMI_A__0': 'value', 'ATOMI_A__NAME': 'value'},
        <String, String>{'ATOMI_A__1': 'value'},
      ];

      // Act
      final Iterable<void Function()> actions = invalidCases.map(
        (Map<String, String> item) =>
            () => environmentToNestedMap(item, prefix: 'ATOMI_'),
      );

      // Assert
      for (final void Function() action in actions) {
        expect(
          action,
          throwsA(
            isA<EnvironmentCoercionException>().having(
              (EnvironmentCoercionException error) => error.toString(),
              'message',
              contains('EnvironmentCoercionException:'),
            ),
          ),
        );
      }
    });
  });
}
