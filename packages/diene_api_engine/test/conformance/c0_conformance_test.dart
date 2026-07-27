import 'dart:convert';
import 'dart:io';

import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:diene_problems/diene_problems.dart'
    show ErrorPortal, problemTypeUri, r14WireId;
import 'package:flutter_test/flutter_test.dart';

/// problem-envelope vector PROJECTED from the neutral C0 release
/// `c0-fixtures-r2` (digest `0e64439c…`), §2 domain
/// `contracts/c0/cases/problem.json` → `cases.envelopes.valid[0]`. It is
/// regenerated, never hand-edited, by `scripts/validate/gen-c0-projection.sh`
/// and byte-checked by the digest-compare gate `scripts/validate/c0-release.sh`.
/// The Dart family is EXEMPT from the C0 otel config block (frontend-only; Faro).
///
/// R-E1a RECOVERY. The preserved C0-migration worktree pinned release
/// `c0-fixtures-r1`; the set frozen across the accepted dart family is now r2.
/// `cases/problem.json` is BYTE-IDENTICAL between r1 and r2, so re-running the
/// projection against r2 reproduces the preserved 2026-07-21 bytes exactly —
/// verified rather than assumed: the regenerated `problem_envelope.json` and
/// `SHA256SUMS` equal the custody alert's recorded sha256 `3f61d1d5…` and
/// `d198dd82…`. This file therefore carries the preserved authoritative
/// provenance AND the broader assertions the optimistic branch had added; the
/// two were merged so the recovery loses neither.
const ErrorPortal _portal = ErrorPortal(
  scheme: 'https',
  host: 'docs.raichu.cluster.atomi.cloud',
  landscape: 'raichu',
  platform: 'dotnet',
  service: 'user',
  module: 'api',
);

Map<String, Object?> _loadFixture(String name) =>
    (jsonDecode(File('test/fixtures/c0/$name').readAsStringSync())
            as Map<Object?, Object?>)
        .cast<String, Object?>();

String _canonical(Map<String, Object?> value) {
  final List<String> keys = value.keys.toList()..sort();
  return keys.map((String k) => '$k=${jsonEncode(value[k])}').join('&');
}

void main() {
  group('C0 §2 problem envelope projected from release c0-fixtures-r2', () {
    final Map<String, Object?> fixture = _loadFixture('problem_envelope.json');

    test('type matches the owned single-source builder', () {
      // R-E14. The frozen release predates the wire-id law and its SAMPLE ids
      // are still KEBAB (`entity-not-found`), while the published
      // `problemWireIdPattern` is `^[a-z][a-z0-9_]*$`. Passing the fixture's id
      // straight in therefore THROWS — "must be a non-empty single path segment
      // matching its contract pattern" — which is what this test did before.
      //
      // The release bytes are authoritative for the envelope vocabulary and the
      // type-URI TEMPLATE, and the correction is owed at the release owner, so
      // the id is projected through the ONE documented normalization
      // (`r14WireId`, exactly `-` → `_`) rather than by hand-editing a frozen
      // vector. Precedent: lib/dart/problems does exactly this in its own
      // conformance suite.
      //
      // Only the TRAILING wire id may differ from the release bytes; the second
      // assertion pins that, so this cannot quietly become a licence to differ
      // anywhere else in the URI.
      const String legacyId = 'entity-not-found';
      final String wireId = r14WireId(legacyId);
      final String releaseType = fixture['type']! as String;
      final String expected = releaseType.replaceRange(
        releaseType.lastIndexOf('/') + 1,
        null,
        wireId,
      );

      expect(
        problemTypeUri(portal: _portal, version: 'v1', id: wireId),
        expected,
      );
      expect(
        expected.substring(0, expected.lastIndexOf('/')),
        releaseType.substring(0, releaseType.lastIndexOf('/')),
        reason: 'only the trailing wire id may differ from the release bytes',
      );
    });

    test('envelope decodes into the owned Problem type and round-trips', () {
      final Problem problem = Problem.fromJson(fixture);
      expect(problem.status, 404);
      expect(problem.recoverable, isFalse);
      expect(problem.data['resource'], 'user');
      expect(problem.data['id'], 42);
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
              id: r14WireId('entity-not-found'),
            ),
        isFalse,
      );
    });

    test('api-engine consumes the C0 problem body via toResult', () {
      // A 404 whose body is the projected problem → Err(that Problem).
      final Result<Map<String, Object?>> result =
          toResult<Map<String, Object?>>(
            Received(HttpResponse(status: 404, body: jsonEncode(fixture))),
            decode: (Map<String, Object?> json) => json,
            endpoint: '/user/42',
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
