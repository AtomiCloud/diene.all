import 'dart:convert';
import 'dart:io';

import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:diene_problems/diene_problems.dart'
    show ErrorPortal, problemTypeUri;
import 'package:test/test.dart';

// Authoritative C0 R2 projection for the D-class API obligation in the frozen
// coverage map. This package claims no identity, config, result-wire, or
// N-class coverage; see test/fixtures/c0/PROVENANCE.md.
const String _releaseId = 'c0-fixtures-r2';
const String _releaseDigest =
    '0e64439c681a22fb4f02285c082ed8ffb7b465e732fde4e49757e9e3c9a5783e';

/// The ErrorPortal assembled from R2 `typeUri.valid[0].segments`.
const ErrorPortal _portal = ErrorPortal(
  scheme: 'https',
  host: 'docs.raichu.cluster.atomi.cloud',
  landscape: 'raichu',
  platform: 'dotnet',
  service: 'user',
  module: 'api',
);

Map<String, Object?> _loadProjection() => _map(
  jsonDecode(File('test/fixtures/c0/problem-envelope.json').readAsStringSync()),
);

Map<String, Object?> _problemEnvelope(Map<String, Object?> projection) =>
    Map<String, Object?>.of(projection)..remove(r'$generated');

Map<String, Object?> _map(Object? value) =>
    Map<String, Object?>.from(value! as Map<dynamic, dynamic>);

String _canonical(Map<String, Object?> json) => jsonEncode(_sortJson(json));

Object? _sortJson(Object? value) {
  if (value is Map<String, Object?>) {
    final List<String> keys = value.keys.toList()..sort();
    return <String, Object?>{
      for (final String key in keys) key: _sortJson(value[key]),
    };
  }
  if (value is List<Object?>) {
    return value.map<Object?>(_sortJson).toList(growable: false);
  }
  return value;
}

void main() {
  group('authoritative C0 R2 API projection', () {
    final Map<String, Object?> projection = _loadProjection();
    final Map<String, Object?> fixture = _problemEnvelope(projection);

    test('records the frozen generated provenance', () {
      expect(_map(projection[r'$generated']), <String, Object?>{
        'generator': 'tool/gen_c0_projection.dart',
        'releaseDigest': _releaseDigest,
        'releaseId': _releaseId,
      });
      expect(projection.keys.toSet(), <String>{
        r'$generated',
        'data',
        'detail',
        'instance',
        'recoverable',
        'status',
        'title',
        'type',
      });
    });

    test('type matches R2 typeUri.valid[0] through the owned builder', () {
      final String expected = problemTypeUri(
        portal: _portal,
        version: 'v1',
        id: 'entity-not-found',
      );
      expect(
        expected,
        'https://docs.raichu.cluster.atomi.cloud/docs/raichu/'
        'dotnet/user/api/v1/entity-not-found',
      );
      expect(fixture['type'], expected);
    });

    test('round-trips the authoritative envelope losslessly', () {
      final Problem problem = Problem.fromJson(fixture);
      expect(problem.status, 404);
      expect(problem.recoverable, isFalse);
      expect(problem.data['id'], 42);
      expect(problem.data['resource'], 'user');
      expect(_canonical(problem.toJson()), _canonical(fixture));
    });

    test('red drill discriminates a mutated type URI', () {
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

    test('api-engine consumes the authoritative problem body via toResult', () {
      final Result<Map<String, Object?>> result =
          toResult<Map<String, Object?>>(
            Received(HttpResponse(status: 404, body: jsonEncode(fixture))),
            decode: (Map<String, Object?> json) => json,
            endpoint: '/user/42',
          );
      expect(result.isErr, isTrue);
      expect(result.unwrapErr().type, fixture['type']);
      expect(result.unwrapErr().status, 404);
      expect(result.unwrapErr().data['id'], 42);
      expect(result.unwrapErr().data['resource'], 'user');
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
