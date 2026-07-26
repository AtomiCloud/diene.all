import 'dart:convert';
import 'dart:io';

import 'package:diene_problems/diene_problems.dart';
import 'package:test/test.dart';

void main() {
  const C0ProblemContract contract = c0ProblemContract;

  group('generated projection identity', () {
    test('JSON projections name the same authenticated release', () {
      for (final String name in <String>[
        'envelope.json',
        'catalog-entry.json',
        'type-uri.json',
      ]) {
        final Map<String, Object?> generated = _map(
          _fixture(name)[r'$generated'],
        );
        expect(generated['generator'], 'tool/gen_c0_projection.dart');
        expect(generated['releaseId'], contract.provenance.releaseId);
        expect(generated['releaseDigest'], contract.provenance.releaseDigest);
      }
    });

    test('JSON projections carry exactly the generated contract cases', () {
      final Map<String, Object?> envelope = _fixture('envelope.json');
      expect(envelope['rfc9457Members'], contract.rfc9457Members);
      expect(envelope['extensions'], contract.extensions);
      expect(envelope['valid'], contract.envelopes['valid']);
      expect(envelope['invalid'], contract.envelopes['invalid']);

      final Map<String, Object?> catalog = _fixture('catalog-entry.json');
      expect(catalog['requiredFields'], contract.catalogEntry['shape']);
      expect(catalog['samples'], contract.catalogEntry['samples']);

      final Map<String, Object?> typeUri = _fixture('type-uri.json');
      expect(typeUri['template'], contract.typeUriTemplate);
      expect(typeUri['valid'], contract.typeUri['valid']);
      expect(typeUri['invalid'], contract.typeUri['invalid']);
    });
  });

  group('C0 §2 envelope', () {
    final List<Object?> valid = _list(contract.envelopes['valid']);
    final List<Object?> invalid = _list(contract.envelopes['invalid']);

    for (int index = 0; index < valid.length; index += 1) {
      test('valid envelope $index carries every contract member', () {
        final Map<String, Object?> sample = _map(valid[index]);
        for (final String field in <String>[
          ...contract.rfc9457Members,
          ...contract.extensions,
        ]) {
          expect(sample.containsKey(field), isTrue, reason: 'missing $field');
        }
        final Problem problem = Problem.fromJson(sample);
        expect(jsonDecode(jsonEncode(problem.toJson())), sample);
      });
    }

    test('invalid envelope set is explicitly release-owned', () {
      expect(invalid, contract.envelopes['invalid']);
    });
  });

  group('C0 §14 catalog entry', () {
    final List<String> required = _list(
      contract.catalogEntry['shape'],
    ).cast<String>();
    final List<Object?> samples = _list(contract.catalogEntry['samples']);

    for (int index = 0; index < samples.length; index += 1) {
      test('catalog sample $index matches the owned emitter', () {
        final Map<String, Object?> sample = _map(samples[index]);
        for (final String field in required) {
          expect(sample.containsKey(field), isTrue, reason: 'missing $field');
        }
        final CatalogEntry entry = CatalogEntry(
          id: sample['id']! as String,
          typeUri: sample['type']! as String,
          title: sample['title']! as String,
          status: sample['status']! as int,
          recoverable: sample['recoverable']! as bool,
          dataSchema: _map(sample['data']),
          endpoints: _list(sample['endpoints'])
              .map(
                (Object? value) => CatalogEndpoint(
                  method: _map(value)['method']! as String,
                  path: _map(value)['path']! as String,
                ),
              )
              .toList(growable: false),
        );
        final Map<String, Object?> emitted = entry.toCrdContent();
        for (final String field in required) {
          expect(emitted[field], sample[field], reason: 'mismatch in $field');
        }
      });
    }
  });

  group('C0 §2 type URI', () {
    final List<Object?> valid = _list(contract.typeUri['valid']);
    final List<Object?> invalid = _list(contract.typeUri['invalid']);

    for (int index = 0; index < valid.length; index += 1) {
      test('valid type URI $index expands through the single builder', () {
        // Arrange. The frozen release predates R-E14 and its SAMPLE ids are
        // still kebab, so the WIRE id is projected through the ONE documented
        // normalization rather than by editing the release bytes. The TEMPLATE
        // and the segment ordering — what this vector is actually the oracle
        // for — are consumed verbatim.
        final Map<String, Object?> vector = _map(valid[index]);
        final Map<String, Object?> segments = _map(vector['segments']);
        final String legacyId = segments['id']! as String;
        final String wireId = r14WireId(legacyId);
        final ErrorPortal portal = ErrorPortal(
          scheme: segments['scheme']! as String,
          host: segments['host']! as String,
          landscape: segments['landscape']! as String,
          platform: segments['platform']! as String,
          service: segments['service']! as String,
          module: segments['module']! as String,
        );
        final String expected = (vector['expectedTypeUri']! as String)
            .replaceRange(
              (vector['expectedTypeUri']! as String).lastIndexOf('/') + 1,
              null,
              wireId,
            );

        // Act.
        final String actual = problemTypeUri(
          portal: portal,
          version: segments['version']! as String,
          id: wireId,
        );

        // Assert.
        expect(actual, expected);
        expect(
          expected.substring(0, expected.lastIndexOf('/')),
          (vector['expectedTypeUri']! as String).substring(
            0,
            (vector['expectedTypeUri']! as String).lastIndexOf('/'),
          ),
          reason: 'only the trailing wire id may differ from the release bytes',
        );
      });
    }

    test('invalid type URI set is explicitly release-owned', () {
      expect(invalid, contract.typeUri['invalid']);
    });
  });
}

Map<String, Object?> _fixture(String name) =>
    _map(jsonDecode(File('test/fixtures/c0/$name').readAsStringSync()));

Map<String, Object?> _map(Object? value) =>
    Map<String, Object?>.from(value! as Map<dynamic, dynamic>);

List<Object?> _list(Object? value) =>
    List<Object?>.from(value! as List<dynamic>);
