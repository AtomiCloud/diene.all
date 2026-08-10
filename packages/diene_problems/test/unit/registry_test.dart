import 'package:diene_problems/diene_problems.dart';
import 'package:test/test.dart';

const _portal = ErrorPortal(
  scheme: 'https',
  host: 'docs.raichu.cluster.atomi.cloud',
  landscape: 'raichu',
  platform: 'dotnet',
  service: 'user',
  module: 'api',
);

void main() {
  group('ProblemRegistry', () {
    test('registers, looks up, and requires types', () {
      final registry = ProblemRegistry(_portal)
        ..register(
          const ProblemType(id: 'x', title: 'X', version: 'v1', status: 400),
        );

      expect(registry.lookup('x')?.id, 'x');
      expect(registry.require('x').id, 'x');
      expect(
        () => registry.require('missing'),
        throwsA(isA<UnknownProblemTypeError>()),
      );
    });

    test('rejects duplicate ids', () {
      final registry = ProblemRegistry(_portal)
        ..register(const ProblemType(id: 'dup', title: 'D', version: 'v1'));
      expect(
        () => registry.register(
          const ProblemType(id: 'dup', title: 'D2', version: 'v1'),
        ),
        throwsA(isA<DuplicateProblemTypeError>()),
      );
    });

    test('typeUriFor builds the URI through the single-source builder', () {
      final registry = ProblemRegistry(_portal)
        ..register(
          const ProblemType(id: 'entity_not_found', title: 'X', version: 'v1'),
        );
      expect(
        registry.typeUriFor(registry.require('entity_not_found')),
        'https://docs.raichu.cluster.atomi.cloud/docs/raichu/dotnet/user/api/v1/entity_not_found',
      );
    });

    test('entries preserve insertion order', () {
      final registry = ProblemRegistry(_portal)
        ..register(const ProblemType(id: 'a', title: 'A', version: 'v1'))
        ..register(const ProblemType(id: 'b', title: 'B', version: 'v1'));
      expect(registry.entries.map((ProblemType t) => t.id).toList(), [
        'a',
        'b',
      ]);
    });
  });

  group('GenericProblems', () {
    test('registers the full baseline set with versioned URIs', () {
      final registry = ProblemRegistry(_portal);
      GenericProblems.registerAll(registry);

      final ids = registry.entries.map((ProblemType t) => t.id).toSet();
      expect(
        ids,
        containsAll(<String>[
          'validation_error',
          'entity_not_found',
          'conflict',
          'unauthenticated',
          'unauthorized',
          'invalid_json',
        ]),
      );
    });

    test('every generic carries a versioned type URI', () {
      final registry = ProblemRegistry(_portal);
      GenericProblems.registerAll(registry);
      for (final ProblemType type in registry.entries) {
        expect(type.version, 'v1');
        expect(registry.typeUriFor(type), contains('/v1/${type.id}'));
      }
    });

    test('seeds itself from the types passed to the constructor', () {
      // Arrange / Act
      final registry = ProblemRegistry(_portal, const <ProblemType>[
        ProblemType(id: 'seeded_one', title: 'One', version: 'v1'),
        ProblemType(id: 'seeded_two', title: 'Two', version: 'v2'),
      ]);
      // Assert
      expect(registry.entries.map((ProblemType t) => t.id), <String>[
        'seeded_one',
        'seeded_two',
      ]);
      expect(
        registry.typeUriFor(registry.require('seeded_two')),
        endsWith('/v2/seeded_two'),
      );
    });

    test('rejects a duplicate seeded id at construction time', () {
      expect(
        () => ProblemRegistry(_portal, const <ProblemType>[
          ProblemType(id: 'dup', title: 'A', version: 'v1'),
          ProblemType(id: 'dup', title: 'B', version: 'v1'),
        ]),
        throwsA(isA<DuplicateProblemTypeError>()),
      );
    });

    test('status defaults match RFC expectations', () {
      expect(GenericProblems.validationError.status, 400);
      expect(GenericProblems.entityNotFound.status, 404);
      expect(GenericProblems.conflict.status, 409);
      expect(GenericProblems.unauthenticated.status, 401);
      expect(GenericProblems.unauthorized.status, 403);
      expect(GenericProblems.invalidJson.status, 400);
    });
  });
}
