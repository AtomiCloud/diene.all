import 'package:diene_core_utils/diene_core_utils.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

void main() {
  group('coerceEnvironmentScalar', () {
    test('a blank value is UNSET', () {
      expect(coerceEnvironmentScalar(''), isNull);
    });

    test('booleans coerce in any case', () {
      for (final String yes in <String>['true', 'TRUE', 'True', 'tRuE']) {
        expect(coerceEnvironmentScalar(yes), true, reason: yes);
      }
      for (final String no in <String>['false', 'FALSE', 'False']) {
        expect(coerceEnvironmentScalar(no), false, reason: no);
      }
    });

    test('safe integers coerce to int, including signs and zero', () {
      expect(coerceEnvironmentScalar('0'), 0);
      expect(coerceEnvironmentScalar('42'), 42);
      expect(coerceEnvironmentScalar('-7'), -7);
      expect(coerceEnvironmentScalar('+7'), 7);
    });

    test('an integer beyond the IEEE-754 safe range stays a String', () {
      // Coercing it would silently lose precision on web builds, so the string
      // boundary is preserved on purpose.
      expect(coerceEnvironmentScalar('9007199254740991'), 9007199254740991);
      expect(coerceEnvironmentScalar('9007199254740992'), '9007199254740992');
      expect(coerceEnvironmentScalar('-9007199254740992'), '-9007199254740992');
    });

    test('decimal and exponent forms coerce to double', () {
      expect(coerceEnvironmentScalar('1.5'), 1.5);
      expect(coerceEnvironmentScalar('-0.25'), -0.25);
      expect(coerceEnvironmentScalar('1e3'), 1000.0);
      expect(coerceEnvironmentScalar('1.5e2'), 150.0);
    });

    test('leading zeros, bare dots, and words stay Strings', () {
      for (final String raw in <String>[
        '007',
        '1.',
        '.5',
        'yes',
        'null',
        '1,5',
        '0x10',
        '  42  ',
      ]) {
        expect(coerceEnvironmentScalar(raw), raw, reason: raw);
      }
    });
  });

  group('environmentToNestedMap', () {
    test('builds a nested object from __-separated paths', () {
      final Result<JsonObject> nested = environmentToNestedMap(<String, String>{
        'ACME_APP__NAME': 'service',
        'ACME_APP__LIMITS__RETRIES': '3',
      }, prefix: 'ACME_');
      expect(nested.unwrap(), <String, Object?>{
        'app': <String, Object?>{
          'name': 'service',
          'limits': <String, Object?>{'retries': 3},
        },
      });
    });

    test('ignores keys outside the prefix', () {
      final Result<JsonObject> nested = environmentToNestedMap(<String, String>{
        'ACME_A': '1',
        'OTHER_B': '2',
        'PATH': '/usr/bin',
      }, prefix: 'ACME_');
      expect(nested.unwrap(), <String, Object?>{'a': 1});
    });

    test('lowercases path components so any YAML spelling merges', () {
      final Result<JsonObject> nested = environmentToNestedMap(<String, String>{
        'ACME_APP__DISPLAY_NAME': 'x',
      }, prefix: 'ACME_');
      expect(nested.unwrap(), <String, Object?>{
        'app': <String, Object?>{'display_name': 'x'},
      });
    });

    test('indexed keys build a list in index order, not key order', () {
      final Result<JsonObject> nested = environmentToNestedMap(<String, String>{
        'ACME_TAGS__1': 'second',
        'ACME_TAGS__0': 'first',
        'ACME_TAGS__2': 'third',
      }, prefix: 'ACME_');
      expect(nested.unwrap(), <String, Object?>{
        'tags': <Object?>['first', 'second', 'third'],
      });
    });

    test('a list of objects materialises at depth', () {
      final Result<JsonObject> nested = environmentToNestedMap(<String, String>{
        'ACME_BACKENDS__0__NAME': 'alpha',
        'ACME_BACKENDS__1__NAME': 'beta',
      }, prefix: 'ACME_');
      expect(nested.unwrap(), <String, Object?>{
        'backends': <Object?>[
          <String, Object?>{'name': 'alpha'},
          <String, Object?>{'name': 'beta'},
        ],
      });
    });

    test('blank values are omitted entirely, never written as null', () {
      final Result<JsonObject> nested = environmentToNestedMap(<String, String>{
        'ACME_A': '',
        'ACME_B': '1',
      }, prefix: 'ACME_');
      expect(nested.unwrap(), <String, Object?>{'b': 1});
      expect(nested.unwrap().containsKey('a'), isFalse);
    });

    test('an empty environment yields an empty object', () {
      expect(
        environmentToNestedMap(<String, String>{}, prefix: 'ACME_').unwrap(),
        isEmpty,
      );
    });

    test('an empty prefix takes every key', () {
      expect(
        environmentToNestedMap(<String, String>{'A': '1'}, prefix: '').unwrap(),
        <String, Object?>{'a': 1},
      );
    });

    test('a key that is only the prefix is rejected', () {
      final Result<JsonObject> nested = environmentToNestedMap(<String, String>{
        'ACME_': 'x',
      }, prefix: 'ACME_');
      _expectCoercionProblem(nested, 'invalid_input', 400);
      expect(nested.unwrapErr().data['field'], 'ACME_');
    });

    test('an empty path component is rejected', () {
      final Result<JsonObject> nested = environmentToNestedMap(<String, String>{
        'ACME_APP____NAME': 'x',
      }, prefix: 'ACME_');
      _expectCoercionProblem(nested, 'invalid_input', 400);
    });

    test('two keys normalising onto the same path conflict', () {
      final Result<JsonObject> nested = environmentToNestedMap(<String, String>{
        'ACME_APP__NAME': 'a',
        'ACME_app__name': 'b',
      }, prefix: 'ACME_');
      _expectCoercionProblem(nested, 'conflict', 409);
      expect(nested.unwrapErr().data['path'], 'name');
    });

    test('a key treating a scalar path as a parent conflicts', () {
      final Result<JsonObject> nested = environmentToNestedMap(<String, String>{
        'ACME_APP': 'scalar',
        'ACME_APP__NAME': 'child',
      }, prefix: 'ACME_');
      _expectCoercionProblem(nested, 'conflict', 409);
      expect(nested.unwrapErr().data['path'], 'app');
    });

    test('mixing indexed and named children is rejected', () {
      final Result<JsonObject> nested = environmentToNestedMap(<String, String>{
        'ACME_TAGS__0': 'a',
        'ACME_TAGS__NAME': 'b',
      }, prefix: 'ACME_');
      _expectCoercionProblem(nested, 'invalid_input', 400);
      expect(nested.unwrapErr().data['field'], contains('tags'));
    });

    test('a list not starting at zero is rejected', () {
      final Result<JsonObject> nested = environmentToNestedMap(<String, String>{
        'ACME_TAGS__1': 'a',
      }, prefix: 'ACME_');
      _expectCoercionProblem(nested, 'invalid_input', 400);
      expect(nested.unwrapErr().title, contains('sparse'));
    });

    test('a sparse list is rejected', () {
      final Result<JsonObject> nested = environmentToNestedMap(<String, String>{
        'ACME_TAGS__0': 'a',
        'ACME_TAGS__2': 'c',
      }, prefix: 'ACME_');
      _expectCoercionProblem(nested, 'invalid_input', 400);
      expect(nested.unwrapErr().title, contains('expected 1'));
    });

    test('a nested failure propagates out of a list element', () {
      final Result<JsonObject> nested = environmentToNestedMap(<String, String>{
        'ACME_BACKENDS__0__PORTS__0': '1',
        'ACME_BACKENDS__0__PORTS__NAME': 'x',
      }, prefix: 'ACME_');
      _expectCoercionProblem(nested, 'invalid_input', 400);
      expect(nested.unwrapErr().data['field'], contains('ports'));
    });

    test('a nested failure propagates out of a named child', () {
      final Result<JsonObject> nested = environmentToNestedMap(<String, String>{
        'ACME_APP__TAGS__0': 'a',
        'ACME_APP__TAGS__NAME': 'x',
      }, prefix: 'ACME_');
      _expectCoercionProblem(nested, 'invalid_input', 400);
    });
  });

  group('environmentPathSeparator', () {
    test('is the C0 double underscore', () {
      expect(environmentPathSeparator, '__');
    });
  });
}

void _expectCoercionProblem(
  Result<Object?> result,
  String expectedCode,
  int expectedStatus,
) {
  expect(result.isErr, isTrue, reason: 'expected a failure, got $result');
  final Problem problem = result.unwrapErr();
  expect(problem.data['util'], 'coercion');
  expect(problem.data['code'], expectedCode);
  expect(problem.data['operation'], 'environmentToNestedMap');
  expect(problem.status, expectedStatus);
  expect(problem.recoverable, isFalse);
  expect(problem.type, endsWith('coercion_$expectedCode'));
}
