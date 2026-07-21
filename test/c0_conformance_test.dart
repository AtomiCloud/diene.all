import 'dart:convert';
import 'dart:io';

import 'package:diene_problems/diene_problems.dart';
import 'package:test/test.dart';

/// C0 §2/§14 conformance — the cross-language contract the Dart family shares
/// with ts/cs/go. The authoritative shapes and samples live in
/// `test/fixtures/c0/*.json` (provenance in that dir's README); this suite
/// LOADS them and validates the library against them. No authoritative value
/// is hard-coded here.

Object? _normalize(Object? value) {
  if (value is Map<String, dynamic>) {
    return value.map((String k, dynamic v) => MapEntry(k, _normalize(v)));
  }
  if (value is List<dynamic>) {
    return value.map(_normalize).toList();
  }
  return value;
}

Map<String, Object?> _fixture(String name) {
  final Object? parsed =
      jsonDecode(File('test/fixtures/c0/$name').readAsStringSync());
  return _normalize(parsed) as Map<String, Object?>;
}

List<String> _stringList(Map<String, Object?> fixture, String key) =>
    (fixture[key]! as List<Object?>).cast<String>();

void main() {
  group('C0 §2 envelope (fixture-authoritative)', () {
    final Map<String, Object?> fixture = _fixture('envelope.json');
    final Map<String, Object?> sample = fixture['sample']! as Map<String, Object?>;

    test('carries every RFC 9457 member plus the data/recoverable extensions',
        () {
      final List<String> expected = <String>[
        ..._stringList(fixture, 'rfc9457Members'),
        ..._stringList(fixture, 'extensions'),
      ];
      for (final String field in expected) {
        expect(sample.containsKey(field), isTrue, reason: 'missing $field');
      }
    });

    test('round-trips losslessly through Problem.fromJson / toJson', () {
      final Problem problem = Problem.fromJson(sample);
      expect(jsonDecode(jsonEncode(problem.toJson())), sample);
    });
  });

  group('C0 §14 catalog entry (fixture-authoritative)', () {
    final Map<String, Object?> fixture = _fixture('catalog-entry.json');
    final List<String> required = _stringList(fixture, 'requiredFields');
    final Map<String, Object?> sample = fixture['sample']! as Map<String, Object?>;

    test('authoritative sample carries every required problems[] field', () {
      for (final String field in required) {
        expect(sample.containsKey(field), isTrue, reason: 'missing $field');
      }
    });

    test('the catalog emitter produces an entry with every required field', () {
      final CatalogEntry entry = CatalogEntry(
        id: sample['id']! as String,
        typeUri: sample['type']! as String,
        title: sample['title']! as String,
        status: (sample['status']! as num).toInt(),
        recoverable: sample['recoverable']! as bool,
        dataSchema: sample['data']! as Map<String, Object?>,
        endpoints: (sample['endpoints']! as List<Object?>)
            .map(
              (Object? e) => CatalogEndpoint(
                method: (e! as Map<String, Object?>)['method']! as String,
                path: (e as Map<String, Object?>)['path']! as String,
              ),
            )
            .toList(),
      );
      final Map<String, Object?> crd = entry.toCrdContent();
      for (final String field in required) {
        expect(crd.containsKey(field), isTrue, reason: 'emitter missing $field');
      }
    });
  });

  group('C0 §2 type URI (fixture-authoritative)', () {
    final Map<String, Object?> fixture = _fixture('type-uri.json');
    final Map<String, Object?> segments =
        fixture['segments']! as Map<String, Object?>;

    test('the single-source builder expands the authoritative template', () {
      final ErrorPortal portal = ErrorPortal(
        scheme: segments['scheme']! as String,
        host: segments['host']! as String,
        landscape: segments['landscape']! as String,
        platform: segments['platform']! as String,
        service: segments['service']! as String,
        module: segments['module']! as String,
      );
      final String uri = problemTypeUri(
        portal: portal,
        version: segments['version']! as String,
        id: segments['id']! as String,
      );
      expect(uri, fixture['expectedTypeUri']);
    });

    test('the fixture encodes the exact C0 §2 template', () {
      expect(
        fixture['template'],
        '{scheme}://{host}/docs/{landscape}/{platform}/{service}/{module}/{version}/{id}',
      );
    });
  });
}
