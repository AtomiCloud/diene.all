import 'package:diene_core_utils/diene_core_utils.dart';
import 'package:test/test.dart';

void main() {
  group('deepClone', () {
    test('rebuilds maps and lists so no mutable structure is shared', () {
      final JsonObject source = <String, Object?>{
        'a': <String, Object?>{
          'b': <Object?>[1, 2],
        },
      };
      final JsonObject clone = deepClone(source)! as JsonObject;

      expect(clone, source);
      expect(identical(clone, source), isFalse);
      final JsonObject clonedInner = clone['a']! as JsonObject;
      (clonedInner['b']! as List<Object?>).add(3);
      expect(
        ((source['a']! as JsonObject)['b']! as List<Object?>),
        <Object?>[1, 2],
        reason: 'mutating the clone reached the source',
      );
    });

    test('passes scalars and null through unchanged', () {
      expect(deepClone(null), isNull);
      expect(deepClone(1), 1);
      expect(deepClone('x'), 'x');
      expect(deepClone(true), true);
      expect(deepClone(1.5), 1.5);
    });
  });

  group('canonicalConfigKey / configKeysMatch', () {
    test('every separator and case spelling canonicalises alike', () {
      for (final String spelling in <String>[
        'display-name',
        'display_name',
        'displayName',
        'DisplayName',
        'DISPLAY_NAME',
        'Display-Name',
      ]) {
        expect(
          canonicalConfigKey(spelling),
          'displayname',
          reason: '$spelling canonicalised wrong',
        );
        expect(configKeysMatch(spelling, 'displayName'), isTrue);
      }
    });

    test('genuinely different keys do not match', () {
      expect(configKeysMatch('displayName', 'display_names'), isFalse);
      expect(canonicalConfigKey(''), '');
    });
  });

  group('deepMerge', () {
    test('merges nested maps recursively', () {
      final JsonObject merged = deepMerge(
        <String, Object?>{
          'app': <String, Object?>{'name': 'base', 'retries': 1},
        },
        <String, Object?>{
          'app': <String, Object?>{'retries': 2},
        },
      );
      expect(merged['app'], <String, Object?>{'name': 'base', 'retries': 2});
    });

    test('lists and scalars replace wholesale — there is no append', () {
      final JsonObject merged = deepMerge(
        <String, Object?>{
          'tags': <Object?>['a', 'b'],
          'n': 1,
        },
        <String, Object?>{
          'tags': <Object?>['c'],
          'n': 2,
        },
      );
      expect(merged['tags'], <Object?>['c']);
      expect(merged['n'], 2);
    });

    test('a map overlaying a scalar replaces it, and vice versa', () {
      expect(
        deepMerge(
          <String, Object?>{'k': 1},
          <String, Object?>{
            'k': <String, Object?>{'nested': true},
          },
        )['k'],
        <String, Object?>{'nested': true},
      );
      expect(
        deepMerge(
          <String, Object?>{
            'k': <String, Object?>{'nested': true},
          },
          <String, Object?>{'k': 1},
        )['k'],
        1,
      );
    });

    test(
      "the base layer's key spelling survives a differently-spelled overlay",
      () {
        final JsonObject merged = deepMerge(
          <String, Object?>{'display-name': 'base'},
          <String, Object?>{'DisplayName': 'overlay'},
        );
        expect(merged.keys, <String>['display-name']);
        expect(merged['display-name'], 'overlay');
      },
    );

    test('an overlay key absent from the base keeps the overlay spelling', () {
      final JsonObject merged = deepMerge(
        <String, Object?>{'a': 1},
        <String, Object?>{'newKey': 2},
      );
      expect(merged.keys, <String>['a', 'newKey']);
    });

    test('two differently-spelled overlay keys collapse onto one output key', () {
      // Both spellings canonicalise alike, so the SECOND must land on the key the
      // first established rather than creating a sibling.
      final JsonObject merged = deepMerge(
        <String, Object?>{},
        <String, Object?>{'display_name': 'first', 'displayName': 'second'},
      );
      expect(merged.keys, <String>['display_name']);
      expect(merged['display_name'], 'second');
    });

    test('neither input is mutated', () {
      final JsonObject base = <String, Object?>{
        'app': <String, Object?>{'name': 'base'},
      };
      final JsonObject overlay = <String, Object?>{
        'app': <String, Object?>{'name': 'overlay'},
      };
      deepMerge(base, overlay);
      expect((base['app']! as JsonObject)['name'], 'base');
      expect((overlay['app']! as JsonObject)['name'], 'overlay');
    });

    test('the merged result shares no structure with either input', () {
      final JsonObject overlay = <String, Object?>{
        'tags': <Object?>['a'],
      };
      final JsonObject merged = deepMerge(<String, Object?>{}, overlay);
      (merged['tags']! as List<Object?>).add('b');
      expect(overlay['tags'], <Object?>['a']);
    });
  });

  group('deepMergeAll', () {
    test('folds layers from lowest to highest precedence', () {
      final JsonObject merged = deepMergeAll(<JsonObject>[
        <String, Object?>{'a': 1, 'b': 1, 'c': 1},
        <String, Object?>{'b': 2, 'c': 2},
        <String, Object?>{'c': 3},
      ]);
      expect(merged, <String, Object?>{'a': 1, 'b': 2, 'c': 3});
    });

    test('no layers yields an empty object', () {
      expect(deepMergeAll(<JsonObject>[]), isEmpty);
    });

    test('one layer is cloned, not aliased', () {
      final JsonObject only = <String, Object?>{'a': 1};
      final JsonObject merged = deepMergeAll(<JsonObject>[only]);
      expect(merged, only);
      expect(identical(merged, only), isFalse);
    });
  });
}
