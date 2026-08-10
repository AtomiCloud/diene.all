import 'dart:convert';

import 'package:diene_core_utils/diene_core_utils.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

void main() {
  group('isJsonObject', () {
    test('accepts string-keyed maps only', () {
      expect(isJsonObject(<String, Object?>{}), isTrue);
      expect(isJsonObject(<String, Object?>{'a': 1}), isTrue);
    });

    test('rejects lists, scalars, null, and non-string-keyed maps', () {
      expect(isJsonObject(<Object?>[]), isFalse);
      expect(isJsonObject(null), isFalse);
      expect(isJsonObject(1), isFalse);
      expect(isJsonObject('x'), isFalse);
      expect(isJsonObject(<int, Object?>{1: 'a'}), isFalse);
    });
  });

  group('stableConfig', () {
    test('sorts object keys at every depth', () {
      final Result<Object?> projected = stableConfig(<String, Object?>{
        'z': 1,
        'a': <String, Object?>{'y': 2, 'b': 3},
      });
      expect(jsonEncode(projected.unwrap()), '{"a":{"b":3,"y":2},"z":1}');
    });

    test('preserves list element order', () {
      final Result<Object?> projected = stableConfig(<Object?>[3, 1, 2]);
      expect(projected.unwrap(), <Object?>[3, 1, 2]);
    });

    test('two structurally equal configs project to identical JSON', () {
      final Object? left = stableConfig(<String, Object?>{
        'b': 1,
        'a': <Object?>[
          <String, Object?>{'d': 4, 'c': 3},
        ],
      }).unwrap();
      final Object? right = stableConfig(<String, Object?>{
        'a': <Object?>[
          <String, Object?>{'c': 3, 'd': 4},
        ],
        'b': 1,
      }).unwrap();
      expect(jsonEncode(left), jsonEncode(right));
    });

    test('scalars and null pass through', () {
      expect(stableConfig(null).unwrap(), isNull);
      expect(stableConfig(7).unwrap(), 7);
      expect(stableConfig('x').unwrap(), 'x');
      expect(stableConfig(true).unwrap(), true);
    });

    test(
      'a value shared across sibling branches is fine (a DAG is not a cycle)',
      () {
        final JsonObject shared = <String, Object?>{'s': 1};
        final Result<Object?> projected = stableConfig(<String, Object?>{
          'left': shared,
          'right': shared,
        });
        expect(projected.isOk, isTrue);
        expect(
          jsonEncode(projected.unwrap()),
          '{"left":{"s":1},"right":{"s":1}}',
        );
      },
    );

    test('a self-referential map is reported, not recursed forever', () {
      final JsonObject cyclic = <String, Object?>{'name': 'root'};
      cyclic['self'] = cyclic;

      final Result<Object?> projected = stableConfig(cyclic);
      expect(projected.isErr, isTrue);
      final Problem problem = projected.unwrapErr();
      expect(problem.status, 422);
      expect(problem.data['util'], 'record');
      expect(problem.data['code'], 'unprojectable');
      expect(problem.data['path'], '<root>.self');
      expect(problem.type, endsWith('record_unprojectable'));
    });

    test('a cycle through a list is also reported', () {
      final List<Object?> cyclic = <Object?>[1];
      cyclic.add(cyclic);

      final Result<Object?> projected = stableConfig(cyclic);
      expect(projected.isErr, isTrue);
      expect(projected.unwrapErr().data['path'], '<root>[1]');
    });

    test('a deeper cycle reports the path where it was found', () {
      final JsonObject inner = <String, Object?>{};
      final JsonObject outer = <String, Object?>{
        'a': <String, Object?>{'b': inner},
      };
      inner['back'] = outer;

      final Result<Object?> projected = stableConfig(outer);
      expect(projected.unwrapErr().data['path'], '<root>.a.b.back');
    });
  });

  group('stableConfigObject', () {
    test('keeps the JsonObject type for a merged configuration', () {
      final JsonObject merged = deepMergeAll(<JsonObject>[
        <String, Object?>{'b': 1},
        <String, Object?>{'a': 2},
      ]);
      final Result<JsonObject> projected = stableConfigObject(merged);
      expect(projected.unwrap(), isA<JsonObject>());
      expect(projected.unwrap().keys, <String>['a', 'b']);
    });

    test('propagates the unprojectable failure', () {
      final JsonObject cyclic = <String, Object?>{};
      cyclic['self'] = cyclic;
      expect(stableConfigObject(cyclic).isErr, isTrue);
    });
  });
}
