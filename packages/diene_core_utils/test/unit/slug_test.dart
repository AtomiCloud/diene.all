import 'package:diene_core_utils/diene_core_utils.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

void main() {
  group('slugify', () {
    test('lowercases and collapses runs of non-alphanumerics', () {
      expect(slugify('Hello World'), 'hello-world');
      expect(slugify('Hello   ---   World'), 'hello-world');
      expect(slugify('a1B2'), 'a1b2');
    });

    test('strips leading and trailing hyphens', () {
      expect(slugify('  --Hello--  '), 'hello');
      expect(slugify('!!!edge!!!'), 'edge');
    });

    test('folds accents away via NFKD rather than dropping the letter', () {
      // The point of NFKD: the base letter SURVIVES and only the mark goes.
      expect(slugify('Crème Brûlée'), 'creme-brulee');
      expect(slugify('Ångström'), 'angstrom');
      expect(slugify('naïve café'), 'naive-cafe');
    });

    test(
      'a string with nothing retainable slugifies to empty, not an error',
      () {
        expect(slugify(''), '');
        expect(slugify('---'), '');
        expect(slugify('!!!'), '');
        expect(slugify('   '), '');
      },
    );

    test('is idempotent on its own output', () {
      for (final String input in <String>[
        'Hello World',
        'Crème Brûlée',
        'a--b',
        '',
      ]) {
        final String once = slugify(input);
        expect(slugify(once), once, reason: 'not idempotent for "$input"');
      }
    });
  });

  group('namespacedKey', () {
    test('composes slugified parts with a colon', () {
      expect(namespacedKey('Diene', 'Core Utils').unwrap(), 'diene:core-utils');
      expect(namespacedKey('  ACME  ', 'App__Name').unwrap(), 'acme:app-name');
    });

    test('accepts raw human text on both sides', () {
      expect(
        namespacedKey('Crème Brûlée', 'Naïve Café').unwrap(),
        'creme-brulee:naive-cafe',
      );
    });

    test('an empty-slugifying namespace fails as a value', () {
      final Result<String> result = namespacedKey('---', 'key');
      expect(result.isErr, isTrue);
      final Problem problem = result.unwrapErr();
      expect(problem.status, 400);
      expect(problem.recoverable, isFalse);
      expect(problem.data['util'], 'slug');
      expect(problem.data['code'], 'invalid_input');
      expect(problem.data['field'], 'namespace');
      expect(problem.data['operation'], 'namespacedKey');
      expect(problem.type, endsWith('slug_invalid_input'));
      expect(
        problem.detail,
        'slug.namespacedKey: namespace must not slugify to empty',
      );
    });

    test('an empty-slugifying key fails as a value naming the key field', () {
      final Result<String> result = namespacedKey('diene', '!!!');
      expect(result.isErr, isTrue);
      expect(result.unwrapErr().data['field'], 'key');
    });

    test(
      'the failure channel composes with the published Result combinators',
      () {
        // Real consumption of diene_result at a package boundary: the Err short-
        // circuits andThen/map exactly as the published monad contract requires.
        int mapped = 0;
        final Result<int> chained = namespacedKey('', 'key')
            .andThen((String key) => Ok<int>(key.length))
            .map((int length) {
              mapped += 1;
              return length * 2;
            });
        expect(chained.isErr, isTrue);
        expect(mapped, 0, reason: 'map ran on an Err');
        expect(chained.unwrapOr(-1), -1);

        final Result<int> ok = namespacedKey('diene', 'core-utils')
            .andThen((String key) => Ok<int>(key.length))
            .map((int length) => length * 2);
        expect(ok.unwrap(), 'diene:core-utils'.length * 2);
        expect(ok.ok().isSome, isTrue);
        expect(ok.err().isNone, isTrue);
      },
    );
  });

  group('NamespacedKeyField', () {
    test('names both components exactly once', () {
      expect(
        NamespacedKeyField.values
            .map((NamespacedKeyField f) => f.name)
            .toList(),
        <String>['namespace', 'key'],
      );
    });
  });
}
