import 'package:diene_problems/diene_problems.dart';
import 'package:diene_problems/test_helper.dart';
import 'package:test/test.dart';

/// Meta tier — builder invariants: the registry-aware builders in
/// `test_helper.dart` always mint valid shapes with single-source type URIs.
void main() {
  group('aProblem', () {
    test('mints a type URI via problemTypeUri (never hand-formatted)', () {
      final p = aProblem(id: 'entity_not_found', version: 'v1');
      expect(
        p.type,
        'https://local.atomi.cloud/docs/local/flutter/app/core/v1/entity_not_found',
      );
    });

    test('honours status/recoverable/data overrides', () {
      final p = aProblem(
        status: 409,
        recoverable: true,
        data: <String, Object?>{'k': 'v'},
      );
      expect(p.status, 409);
      expect(p.recoverable, true);
      expect(p.data, {'k': 'v'});
    });

    test('round-trips through Problem.fromJson', () {
      final p = aProblem();
      expect(Problem.fromJson(p.toJson()), p);
    });

    test('accepts a custom portal', () {
      const portal = ErrorPortal(
        scheme: 'https',
        host: 'h',
        landscape: 'l',
        platform: 'p',
        service: 's',
        module: 'm',
      );
      expect(
        aProblem(portal: portal, id: 'x').type,
        'https://h/docs/l/p/s/m/v1/x',
      );
    });
  });

  group('anErrorPortal', () {
    test('builds a portal whose URI is well-formed', () {
      final portal = anErrorPortal();
      final uri = problemTypeUri(portal: portal, version: 'v1', id: 'x');
      expect(uri, startsWith('https://'));
      expect(uri, contains('/docs/'));
    });
  });

  group('aCatalogEntry', () {
    test('mints a single-source type URI and renders valid CR content', () {
      final entry = aCatalogEntry(
        id: 'validation_error',
        status: 400,
        recoverable: true,
      );
      expect(entry.typeUri, contains('/v1/validation_error'));
      final crd = entry.toCrdContent();
      expect(crd['id'], 'validation_error');
      expect(crd['status'], 400);
      expect(crd['recoverable'], true);
      expect(crd['endpoints'], <Object?>[]);
    });

    test('carries declared endpoints', () {
      final entry = aCatalogEntry(
        id: 'x',
        endpoints: const <CatalogEndpoint>[
          CatalogEndpoint(method: 'GET', path: '/x'),
        ],
      );
      expect((entry.toCrdContent()['endpoints'] as List<Object?>).length, 1);
    });
  });
}
