import 'dart:convert';
import 'dart:io';

import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:diene_problems/diene_problems.dart'
    show ErrorPortal, problemTypeUri;
import 'package:test/test.dart';

/// LOCAL problem-envelope vectors (C0 §2-SHAPED), NOT authoritative C0
/// fixtures. Authoritative, source-owned C0 fixture conformance is
/// INTEGRATION-HELD pending the C0 owner (see `test/fixtures/c0/PROVENANCE.md`
/// and the node note); these are kept only as local behavioural tests of this
/// engine's problem-envelope handling. The Dart family is EXEMPT from the C0
/// otel config block (frontend-only; Faro).

/// The documented ErrorPortal the fixture's type URI is built from (C0 §2).
const ErrorPortal _portal = ErrorPortal(
  scheme: 'https',
  host: 'docs.raichu.cluster.atomi.cloud',
  landscape: 'raichu',
  platform: 'diene',
  service: 'sample',
  module: 'users',
);

Map<String, Object?> _loadFixture(String name) =>
    jsonDecode(File('test/fixtures/c0/$name').readAsStringSync())
        as Map<String, Object?>;

String _canonical(Map<String, Object?> json) {
  final List<String> keys = json.keys.toList()..sort();
  return jsonEncode(<String, Object?>{for (final String k in keys) k: json[k]});
}

void main() {
  group('local problem-envelope vector (C0-shaped; authoritative HELD)', () {
    final Map<String, Object?> fixture = _loadFixture('problem_envelope.json');

    test('type matches the owned single-source builder (local check)', () {
      // Local consistency check: the vector's type equals the C0 §2 template
      // output — a hand-edited type fails here. This is NOT authoritative C0
      // fixture provenance (that is integration-held pending the C0 owner).
      expect(
        fixture['type'],
        problemTypeUri(portal: _portal, version: 'v1', id: 'entity-not-found'),
      );
    });

    test('round-trips losslessly through diene_result Problem', () {
      final Problem problem = Problem.fromJson(fixture);
      expect(problem.status, 404);
      expect(problem.recoverable, isFalse);
      expect(problem.data['entity'], 'user');
      // Canonical round-trip equality.
      expect(_canonical(problem.toJson()), _canonical(fixture));
    });

    test('gate discriminates a mutated fixture (red drill)', () {
      final Map<String, Object?> mutated = <String, Object?>{
        ...fixture,
        'type': 'https://evil.example.com/not/the/template',
      };
      expect(
        mutated['type'] ==
            problemTypeUri(
              portal: _portal,
              version: 'v1',
              id: 'entity-not-found',
            ),
        isFalse,
      );
    });

    test('api-engine consumes the C0 problem body via toResult', () {
      // A 404 whose body is the fixture problem → Err(that Problem).
      final Result<Map<String, Object?>> result =
          toResult<Map<String, Object?>>(
            Received(HttpResponse(status: 404, body: jsonEncode(fixture))),
            decode: (Map<String, Object?> json) => json,
            endpoint: '/users/42',
          );
      expect(result.isErr, isTrue);
      expect(result.unwrapErr().type, fixture['type']);
      expect(result.unwrapErr().status, 404);
    });
  });

  group('engine-owned config block schema (api-engine ownership)', () {
    test('is frozen (drift guard) and carries NO otel block', () {
      final Map<String, Object?> schema = ApiEngineConfig.schema;
      expect(schema[r'$id'], 'urn:diene:config-block:api-engine');
      final Map<String, Object?> properties =
          schema['properties']! as Map<String, Object?>;
      expect(properties.containsKey('otel'), isFalse);
      expect(properties.keys, containsAll(<String>['backends', 'rescue']));
    });
  });
}
