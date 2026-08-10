import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

const String _fixturePath = 'test/fixtures/c0/result-wire.json';
const String _checksumPath = 'test/fixtures/c0/SHA256SUMS';

/// C0 §5 Result/Option wire conformance, driven by the source-owned projection
/// of the frozen release `c0-fixtures-r2`
/// (`test/fixtures/c0/result-wire.json`, generated 1:1 from
/// `contracts/c0/cases/result-wire.json` by `tool/gen_c0_projection.dart`).
void main() {
  final Map<String, Object?> fixture = _fixture();
  final Map<String, Object?> generated =
      (fixture[r'$generated']! as Map<Object?, Object?>)
          .cast<String, Object?>();
  final Map<String, Object?> results =
      (fixture['results']! as Map<Object?, Object?>).cast<String, Object?>();
  final Map<String, Object?> options =
      (fixture['options']! as Map<Object?, Object?>).cast<String, Object?>();

  test('projection declares its authoritative C0 release provenance', () {
    expect(generated['releaseId'], 'c0-fixtures-r2');
    expect(
      generated['releaseDigest'],
      '0e64439c681a22fb4f02285c082ed8ffb7b465e732fde4e49757e9e3c9a5783e',
    );
  });

  test('projection bytes match the frozen checksum ledger', () {
    final File fixtureFile = File(_fixturePath);
    final List<String> checksumFields = File(
      _checksumPath,
    ).readAsStringSync().trim().split(RegExp(r'\s+'));

    expect(checksumFields, hasLength(2));
    expect(checksumFields[1], 'result-wire.json');
    expect(
      sha256.convert(fixtureFile.readAsBytesSync()).toString(),
      checksumFields[0],
    );
  });

  group('Result wire — valid vectors round-trip', () {
    for (final Map<String, Object?> vector in _cases(results['valid'])) {
      test(vector['name']! as String, () {
        // Arrange
        final ResultSerial wire = _wire(vector);

        // Act
        final Result<Object?> decoded = Result<Object?>.fromSerial(
          wire,
          decodeOk: (Object? value) => value,
        );
        final ResultSerial encoded = decoded.serial();

        // Assert
        expect(encoded, equals(wire));
        if (vector['name'] == 'err-problem') {
          final Problem problem = decoded.unwrapErr();
          expect(problem, isA<Problem>());
          expect(problem.toJson(), equals(wire[1]));
        }
      });
    }
  });

  group('Option wire — valid vectors round-trip', () {
    for (final Map<String, Object?> vector in _cases(options['valid'])) {
      test(vector['name']! as String, () {
        // Arrange
        final OptionSerial wire = _wire(vector);

        // Act
        final Option<Object?> decoded = Option<Object?>.fromSerial(
          wire,
          decodeSome: (Object? value) => value,
        );

        // Assert
        expect(decoded.serial(), equals(wire));
        switch (vector['name']) {
          case 'some-null':
            expect(decoded.isSome, isTrue);
            expect(decoded.native(), isNull);
          case 'none':
            expect(decoded.isNone, isTrue);
        }
      });
    }
  });

  group('Result wire — invalid vectors are rejected', () {
    for (final Map<String, Object?> vector in _cases(results['invalid'])) {
      test(vector['name']! as String, () {
        final ResultSerial wire = _wire(vector);
        expect(
          () => Result<Object?>.fromSerial(
            wire,
            decodeOk: (Object? value) => value,
          ),
          throwsFormatException,
        );
      });
    }
  });

  group('Option wire — invalid vectors are rejected', () {
    // Includes the `none-non-null` semantic rejection (`['none', 1]`).
    for (final Map<String, Object?> vector in _cases(options['invalid'])) {
      test(vector['name']! as String, () {
        final OptionSerial wire = _wire(vector);
        expect(
          () => Option<Object?>.fromSerial(
            wire,
            decodeSome: (Object? value) => value,
          ),
          throwsFormatException,
        );
      });
    }
  });

  test('public combinator surface covers the contract names', () {
    final List<String> combinators = (fixture['combinators']! as List<Object?>)
        .cast<String>();
    expect(
      combinators,
      containsAll(<String>['map', 'mapErr', 'andThen', 'match']),
    );

    // Compile-time usage of every named public combinator on one vector.
    final Result<int> chained = const Result<int>.ok(1)
        .map((int value) => value + 1)
        .mapErr((Problem problem) => problem)
        .andThen((int value) => Result<int>.ok(value));
    final String tag = chained.match(
      ok: (int _) => 'ok',
      err: (Problem _) => 'err',
    );
    expect(tag, 'ok');
  });
}

Map<String, Object?> _fixture() {
  final String source = File(_fixturePath).readAsStringSync();
  return (jsonDecode(source)! as Map<Object?, Object?>).cast<String, Object?>();
}

List<Map<String, Object?>> _cases(Object? raw) => (raw! as List<Object?>)
    .map(
      (Object? entry) =>
          (entry! as Map<Object?, Object?>).cast<String, Object?>(),
    )
    .toList();

List<Object?> _wire(Map<String, Object?> vector) =>
    List<Object?>.from(vector['wire']! as List<Object?>);
