import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:diene_dart_lib/diene_dart_lib.dart';
import 'package:test/test.dart';

void main() {
  const String fixturesPath = 'test/fixtures/c0';
  final Map<String, Object?> manifest = _readJson(
    File('$fixturesPath/manifest.json'),
  );

  test('manifest declares its local, non-authoritative provenance', () {
    expect(manifest['authority'], 'local-regression-only');
    expect(manifest['algorithm'], 'sha256');
  });

  final Map<String, Object?> fixtures =
      (manifest['fixtures']! as Map<Object?, Object?>).cast<String, Object?>();

  test('manifest pins at least one fixture', () {
    expect(fixtures, isNotEmpty);
  });

  group('C0 Note wire fixtures', () {
    fixtures.forEach((String name, Object? rawDigest) {
      test(name, () {
        // Arrange
        final File file = File('$fixturesPath/$name');
        final List<int> bytes = file.readAsBytesSync();
        final String expectedDigest = rawDigest! as String;

        // Act — recompute the pinned digest.
        final String actualDigest = sha256.convert(bytes).toString();

        // Assert — a corrupted fixture or drifted manifest reddens here.
        expect(
          actualDigest,
          expectedDigest,
          reason: 'fixture "$name" digest drifted from the manifest',
        );

        // Act — decode -> encode -> decode round trip through the codec.
        final Map<String, Object?> wire = _decodeObject(utf8.decode(bytes));
        final Note decoded = Note.fromJson(wire);
        final Map<String, Object?> encoded = decoded.toJson();
        final Note reDecoded = Note.fromJson(
          _decodeObject(jsonEncode(encoded)),
        );

        // Assert — a broken codec reddens here.
        expect(encoded, wire);
        expect(reDecoded, decoded);
      });
    });
  });
}

Map<String, Object?> _readJson(File file) =>
    _decodeObject(file.readAsStringSync());

Map<String, Object?> _decodeObject(String source) =>
    (jsonDecode(source)! as Map<Object?, Object?>).cast<String, Object?>();
