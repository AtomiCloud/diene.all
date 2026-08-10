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
  group('fromObject', () {
    test('returns an already-typed Problem unchanged', () {
      const problem = Problem(type: 't', title: 'T', status: 500);
      expect(fromObject(problem), same(problem));
    });

    test('maps a known id on a Map to the registry type', () {
      // Arrange
      final registry = ProblemRegistry(_portal)
        ..register(GenericProblems.entityNotFound);
      final error = <String, Object?>{
        'problemId': 'entity_not_found',
        'data': <String, Object?>{'resource': 'user'},
      };
      // Act
      final p = fromObject(
        error,
        options: TransformOptions(registry: registry, portal: _portal),
      );
      // Assert
      expect(p.status, 404);
      expect(p.recoverable, false);
      expect(p.type, contains('/v1/entity_not_found'));
      expect(p.data, {'resource': 'user'});
    });

    test('falls back to an uncatalogued problem for an unknown value', () {
      final p = fromObject(
        StateError('boom'),
        options: const TransformOptions(portal: _portal),
      );
      expect(p.status, 500);
      expect(p.recoverable, false);
      expect(p.type, contains('/$uncataloguedProblemId'));
      expect(p.detail, contains('boom'));
    });

    test('falls back to uncatalogued when no registry is supplied', () {
      final p = fromObject(<String, Object?>{'problemId': 'entity_not_found'});
      expect(p.type, contains('/$uncataloguedProblemId'));
    });

    test(
      'falls back to uncatalogued when the registry does not know the id',
      () {
        final registry = ProblemRegistry(_portal);
        final p = fromObject(<String, Object?>{
          'problemId': 'nope',
        }, options: TransformOptions(registry: registry, portal: _portal));
        expect(p.type, contains('/$uncataloguedProblemId'));
      },
    );

    test('honours a custom default status', () {
      final p = fromObject(
        'oops',
        options: const TransformOptions(portal: _portal, defaultStatus: 503),
      );
      expect(p.status, 503);
    });
  });
}
