import 'dart:convert';
import 'dart:io';

import 'package:diene_core_utils/diene_core_utils.dart';
import 'package:test/test.dart';

/// C0 §1 temporal conformance — the cross-language wire-format contract the
/// Dart family shares with the ts/cs/go families.
///
/// Every case is drawn from the authoritative fixture artifact
/// `test/fixtures/c0_temporal.json`; this suite never creates ad hoc temporal
/// values of its own, so it fails if the package diverges from the shared C0
/// cases (including the IANA release baked into [isIanaTimeZone]).
void main() {
  final Map<String, Object?> fixture = jsonDecode(
    File('test/fixtures/c0_temporal.json').readAsStringSync(),
  ) as Map<String, Object?>;

  List<String> cases(String domain, String polarity) =>
      ((fixture[domain]! as Map<String, Object?>)[polarity]! as List<Object?>)
          .cast<String>();

  group('C0 §1 provenance', () {
    test('fixture is bound to the bundled IANA release', () {
      final Map<String, Object?> provenance =
          fixture[r'$provenance']! as Map<String, Object?>;
      expect(provenance['ianaRelease'], ianaTimeZoneRelease);
      expect(provenance['contract'], contains('C0 §1'));
    });
  });

  group('C0 §1 date YYYY-MM-DD', () {
    const WireCodec codec = WireCodec();
    for (final String value in cases('date', 'valid')) {
      test('accepts and round-trips $value', () {
        expect(codec.encodeDate(codec.decodeDate(value)), value);
      });
    }
    for (final String value in cases('date', 'invalid')) {
      test('rejects ${value.isEmpty ? '<empty>' : value}', () {
        expect(() => codec.decodeDate(value), throwsFormatException);
      });
    }
  });

  group('C0 §1 time HH:mm:ss', () {
    const WireCodec codec = WireCodec();
    for (final String value in cases('time', 'valid')) {
      test('accepts and round-trips $value', () {
        expect(codec.encodeTime(codec.decodeTime(value)), value);
      });
    }
    for (final String value in cases('time', 'invalid')) {
      test('rejects ${value.isEmpty ? '<empty>' : value}', () {
        expect(() => codec.decodeTime(value), throwsFormatException);
      });
    }
  });

  group('C0 §1 RFC 3339 UTC instant', () {
    const WireCodec codec = WireCodec();
    for (final String value in cases('instant', 'valid')) {
      test('accepts $value as a UTC instant', () {
        expect(codec.decodeInstant(value).isUtc, isTrue);
      });
    }
    for (final String value in cases('instant', 'invalid')) {
      test('rejects ${value.isEmpty ? '<empty>' : value}', () {
        expect(() => codec.decodeInstant(value), throwsFormatException);
      });
    }
  });

  group('C0 §1 ISO 8601 duration', () {
    const WireCodec codec = WireCodec();
    for (final String value in cases('duration', 'valid')) {
      test('accepts and round-trips $value', () {
        expect(codec.encodeDuration(codec.decodeDuration(value)), value);
      });
    }
    for (final String value in cases('duration', 'invalid')) {
      test('rejects ${value.isEmpty ? '<empty>' : value}', () {
        expect(() => codec.decodeDuration(value), throwsFormatException);
      });
    }
  });

  group('C0 §1 IANA timezone identifier', () {
    const WireCodec codec = WireCodec();
    for (final String value in cases('timezone', 'valid')) {
      test('accepts and round-trips $value', () {
        expect(isIanaTimeZone(value), isTrue);
        expect(codec.encodeTimezone(codec.decodeTimezone(value)), value);
      });
    }
    for (final String value in cases('timezone', 'invalid')) {
      test('rejects ${value.isEmpty ? '<empty>' : value}', () {
        expect(isIanaTimeZone(value), isFalse);
        expect(() => codec.decodeTimezone(value), throwsFormatException);
      });
    }
  });
}
