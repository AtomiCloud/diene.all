import 'package:diene_problems/diene_problems.dart';
import 'package:test/test.dart';

/// C0 §2/§14 conformance — the cross-language contract the Dart family shares
/// with ts/cs/go: the envelope shape, the `data` extension, the versioned
/// `{version}` type URI, and the catalog `problems[]` CR shape.
void main() {
  group('C0 §2 envelope', () {
    test('carries the five RFC 9457 members plus data + recoverable', () {
      const problem = Problem(
        type: 'https://h/docs/l/p/s/m/v1/id',
        title: 'T',
        status: 409,
        detail: 'd',
        instance: 'i',
        recoverable: true,
        data: <String, Object?>{'k': 'v'},
      );
      final json = problem.toJson();
      // RFC 9457 canonical members
      for (final field in <String>['type', 'title', 'status', 'detail', 'instance']) {
        expect(json.containsKey(field), isTrue, reason: 'missing RFC 9457 member $field');
      }
      // Atomi extensions
      expect(json.containsKey('data'), isTrue);
      expect(json.containsKey('recoverable'), isTrue);
    });

    test('round-trips losslessly through JSON', () {
      const problem = Problem(
        type: 'https://h/docs/l/p/s/m/v1/id',
        title: 'T',
        status: 422,
        detail: 'd',
        recoverable: true,
        data: <String, Object?>{
          'n': 1,
          'nested': <String, Object?>{'a': <String>['x', 'y']},
        },
      );
      expect(Problem.fromJson(problem.toJson()), problem);
    });
  });

  group('C0 §2 versioned type URI', () {
    test('a version bump mints a distinct type URI', () {
      const portal = ErrorPortal(
        scheme: 'https',
        host: 'h',
        landscape: 'l',
        platform: 'p',
        service: 's',
        module: 'm',
      );
      final v1 = problemTypeUri(portal: portal, version: 'v1', id: 'x');
      final v2 = problemTypeUri(portal: portal, version: 'v2', id: 'x');
      expect(v1, isNot(equals(v2)));
      expect(v1, contains('/v1/x'));
      expect(v2, contains('/v2/x'));
    });
  });

  group('C0 §14 catalog CR shape', () {
    test('each problems[] entry has id/type/title/status/recoverable/data/endpoints', () {
      final catalog = ProblemCatalog(portal: ErrorPortal.localError)
        ..addType(
          GenericProblems.validationError,
          endpoints: const <CatalogEndpoint>[CatalogEndpoint(method: 'POST', path: '/x')],
        );
      final crd = catalog.toCrdContent().single;
      for (final field in <String>[
        'id',
        'type',
        'title',
        'status',
        'recoverable',
        'data',
        'endpoints',
      ]) {
        expect(crd.containsKey(field), isTrue, reason: 'missing C0 §14 field $field');
      }
      expect(crd['endpoints'], isA<List<Object?>>());
    });
  });
}
