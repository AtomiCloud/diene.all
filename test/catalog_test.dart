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
  group('CatalogEndpoint', () {
    test('renders method + path', () {
      final json = const CatalogEndpoint(method: 'POST', path: '/user').toJson();
      expect(json, {'method': 'POST', 'path': '/user'});
    });
  });

  group('CatalogEntry', () {
    test('toCrdContent renders the C0 §14 problems[] shape', () {
      final crd = const CatalogEntry(
        id: 'validation-error',
        typeUri: 'https://h/docs/raichu/dotnet/user/api/v1/validation-error',
        title: 'Validation error',
        status: 400,
        recoverable: true,
        dataSchema: <String, Object?>{'type': 'object'},
        endpoints: <CatalogEndpoint>[CatalogEndpoint(method: 'POST', path: '/user')],
      ).toCrdContent();

      expect(crd['id'], 'validation-error');
      expect(crd['type'], 'https://h/docs/raichu/dotnet/user/api/v1/validation-error');
      expect(crd['title'], 'Validation error');
      expect(crd['status'], 400);
      expect(crd['recoverable'], true);
      expect(crd['data'], {'type': 'object'});
      expect(crd['endpoints'], [
        {'method': 'POST', 'path': '/user'},
      ]);
    });
  });

  group('ProblemCatalog', () {
    test('addType builds the type URI via the single-source builder', () {
      final catalog = ProblemCatalog(portal: _portal)
        ..addType(GenericProblems.entityNotFound);

      final entry = catalog.lookup('entity-not-found')!;
      expect(
        entry.typeUri,
        'https://docs.raichu.cluster.atomi.cloud/docs/raichu/dotnet/user/api/v1/entity-not-found',
      );
      expect(entry.status, 404);
      expect(entry.recoverable, GenericProblems.entityNotFound.recoverable);
    });

    test('addGenerics emits all baseline entries with the recoverable flag', () {
      final catalog = ProblemCatalog(portal: _portal)..addGenerics();
      final crd = catalog.toCrdContent();

      final byId = {
        for (final Map<String, Object?> e in crd) e['id'] as String: e,
      };
      expect(byId.keys, containsAll(GenericProblems.all.map((ProblemType t) => t.id)));
      // recoverable flag is present and reflects the declared type
      expect(byId['validation-error']!['recoverable'], true);
      expect(byId['entity-not-found']!['recoverable'], false);
    });

    test('toCrdContent carries endpoints declared per entry', () {
      final catalog = ProblemCatalog(portal: _portal)
        ..addType(
          GenericProblems.validationError,
          endpoints: const <CatalogEndpoint>[
            CatalogEndpoint(method: 'POST', path: '/user'),
            CatalogEndpoint(method: 'PATCH', path: '/user/{id}'),
          ],
        );
      final crd = catalog.toCrdContent().single;
      expect((crd['endpoints'] as List<Object?>).length, 2);
    });

    test('add replaces an existing entry by id', () {
      final catalog = ProblemCatalog(portal: _portal)
        ..add(const CatalogEntry(
          id: 'x',
          typeUri: 'u1',
          title: 'X',
          status: 400,
          recoverable: false,
        ))
        ..add(const CatalogEntry(
          id: 'x',
          typeUri: 'u2',
          title: 'X2',
          status: 422,
          recoverable: true,
        ));
      expect(catalog.entries.length, 1);
      expect(catalog.lookup('x')?.status, 422);
      expect(catalog.toCrdContent().length, 1);
    });

    test('toCrdContent preserves insertion order', () {
      final catalog = ProblemCatalog(portal: _portal)
        ..addType(GenericProblems.validationError)
        ..addType(GenericProblems.entityNotFound);
      final ids = catalog.toCrdContent().map((Map<String, Object?> e) => e['id'] as String).toList();
      expect(ids, ['validation-error', 'entity-not-found']);
    });
  });
}
