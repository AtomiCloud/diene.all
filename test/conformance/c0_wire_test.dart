import 'dart:convert';
import 'dart:io';

import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

void main() {
  final Map<String, Object?> fixture = _fixture();

  group('C0 Result wire fixtures', () {
    for (final Object? rawCase in fixture['results']! as List<Object?>) {
      final Map<String, Object?> fixtureCase =
          (rawCase! as Map<Object?, Object?>).cast<String, Object?>();

      test(fixtureCase['name']! as String, () {
        // Arrange
        final ResultSerial wire = List<Object?>.from(
          fixtureCase['wire']! as List<Object?>,
        );

        // Act
        final Result<Object?> decoded = Result<Object?>.fromSerial(
          wire,
          decodeOk: (Object? value) => value,
        );
        final ResultSerial encoded = decoded.serial();

        // Assert
        expect(encoded, equals(wire));
      });
    }
  });

  group('C0 Option wire fixtures', () {
    for (final Object? rawCase in fixture['options']! as List<Object?>) {
      final Map<String, Object?> fixtureCase =
          (rawCase! as Map<Object?, Object?>).cast<String, Object?>();

      test(fixtureCase['name']! as String, () {
        // Arrange
        final OptionSerial wire = List<Object?>.from(
          fixtureCase['wire']! as List<Object?>,
        );

        // Act
        final Option<Object?> decoded = Option<Object?>.fromSerial(
          wire,
          decodeSome: (Object? value) => value,
        );
        final OptionSerial encoded = decoded.serial();

        // Assert
        expect(encoded, equals(wire));
      });
    }
  });
}

Map<String, Object?> _fixture() {
  final String source = File(
    'test/fixtures/c0/result_wire.json',
  ).readAsStringSync();
  return (jsonDecode(source)! as Map<Object?, Object?>).cast<String, Object?>();
}
