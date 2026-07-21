import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:diene_core_utils/diene_core_utils.dart';
import 'package:test/test.dart';

/// C0 §1 temporal conformance — driven entirely from the shared, version-pinned
/// [c0TemporalContract] that `diene_core_utils` owns for the Dart family. The
/// suite creates no ad hoc temporal values and reads neither host IANA data nor
/// the host clock: every timezone and clock vector is injected from the
/// contract. Downstream family packages consume the same contract, so a package
/// that diverges from it turns its conformance suite red.
void main() {
  const WireCodec codec = WireCodec();
  const C0TemporalContract contract = c0TemporalContract;

  group('C0 §1 contract provenance and stale detection', () {
    test('pins the bundled IANA release', () {
      expect(contract.provenance.ianaRelease, ianaTimeZoneRelease);
      expect(contract.provenance.c0Section, contains('C0 §1'));
    });

    test('recorded content digest matches the live vectors', () {
      final String actual =
          sha256.convert(utf8.encode(contract.digestPayload())).toString();
      expect(
        actual,
        contract.provenance.contentSha256,
        reason: 'C0 temporal vectors changed without updating contentSha256; '
            'recompute and update lib/src/c0_temporal_contract.dart.',
      );
    });
  });

  group('C0 §1 date YYYY-MM-DD', () {
    for (final String value in contract.dates.valid) {
      test('accepts and round-trips $value', () {
        expect(codec.encodeDate(codec.decodeDate(value)), value);
      });
    }
    for (final String value in contract.dates.invalid) {
      test('rejects ${_label(value)}', () {
        expect(() => codec.decodeDate(value), throwsFormatException);
      });
    }
  });

  group('C0 §1 time HH:mm:ss', () {
    for (final String value in contract.times.valid) {
      test('accepts and round-trips $value', () {
        expect(codec.encodeTime(codec.decodeTime(value)), value);
      });
    }
    for (final String value in contract.times.invalid) {
      test('rejects ${_label(value)}', () {
        expect(() => codec.decodeTime(value), throwsFormatException);
      });
    }
  });

  group('C0 §1 RFC 3339 UTC instant (injected clock)', () {
    for (final C0InstantVector vector in contract.instants) {
      test('normalizes ${vector.input} to ${vector.canonicalUtc}', () {
        expect(
          codec.encodeInstant(DateTime.parse(vector.input)),
          vector.canonicalUtc,
        );
        // The canonical UTC form round-trips through the strict parser.
        expect(codec.decodeInstant(vector.canonicalUtc).isUtc, isTrue);
      });
    }
    for (final String value in contract.invalidInstants) {
      test('rejects ${_label(value)}', () {
        expect(() => codec.decodeInstant(value), throwsFormatException);
      });
    }
  });

  group('C0 §1 ISO 8601 duration', () {
    for (final String value in contract.durations.valid) {
      test('accepts and round-trips $value', () {
        expect(codec.encodeDuration(codec.decodeDuration(value)), value);
      });
    }
    for (final String value in contract.durations.invalid) {
      test('rejects ${_label(value)}', () {
        expect(() => codec.decodeDuration(value), throwsFormatException);
      });
    }
  });

  group('C0 §1 IANA timezone identifier (contract-settled)', () {
    for (final String value in contract.timezones.valid) {
      test('accepts and round-trips $value', () {
        expect(isIanaTimeZone(value), isTrue);
        expect(codec.encodeTimezone(codec.decodeTimezone(value)), value);
      });
    }
    for (final String value in contract.timezones.invalid) {
      test('rejects ${_label(value)}', () {
        expect(isIanaTimeZone(value), isFalse);
        expect(() => codec.decodeTimezone(value), throwsFormatException);
      });
    }
  });
}

String _label(String value) => value.isEmpty ? '<empty>' : value;
