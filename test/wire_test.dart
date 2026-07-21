import 'package:diene_core_utils/diene_core_utils.dart';
import 'package:test/test.dart';

/// Behavioral unit tests for the wire value types. The cross-language C0
/// contract cases live in `c0_conformance_test.dart`, which drives them from
/// the shared fixture artifact; this file covers construction, equality, and
/// formatter behavior that is not part of that fixture surface.
void main() {
  const WireCodec codec = WireCodec();

  test('value constructors and parsers agree on identity and hashing', () {
    // Arrange
    final WireDate date = WireDate(2026, 7, 21);
    final WireTime time = WireTime(1, 2, 3);
    final IsoDuration duration = IsoDuration.parse('P1DT2H3M4.5S');
    final IanaTimezone timezone = IanaTimezone.parse('Asia/Singapore');

    // Act / Assert
    expect(codec.encodeDate(date), '2026-07-21');
    expect(codec.encodeTime(time), '01:02:03');
    expect(date, WireDate.parse('2026-07-21'));
    expect(date.hashCode, WireDate.parse('2026-07-21').hashCode);
    expect(time, WireTime.parse('01:02:03'));
    expect(time.hashCode, WireTime.parse('01:02:03').hashCode);
    expect(duration, IsoDuration.parse('P1DT2H3M4.5S'));
    expect(duration.hashCode, IsoDuration.parse('P1DT2H3M4.5S').hashCode);
    expect(timezone, IanaTimezone.parse('Asia/Singapore'));
    expect(timezone.hashCode, IanaTimezone.parse('Asia/Singapore').hashCode);
    // A wire value never equals a value of a different type.
    final Object otherType = time;
    expect(date == otherType, isFalse);
  });

  test('RFC 3339 formatter normalizes a local offset to a UTC Z instant', () {
    // Arrange
    final DateTime offset = DateTime.parse('2026-07-21T09:02:03+08:00');

    // Act
    final String actual = formatRfc3339Utc(offset);

    // Assert
    expect(actual, '2026-07-21T01:02:03.000Z');
  });

  test('wire value constructors reject invalid component ranges', () {
    // Arrange / Act / Assert
    expect(() => WireDate(0, 1, 1), throwsFormatException);
    expect(() => WireDate(2026, 2, 30), throwsFormatException);
    expect(() => WireTime(1, 60, 1), throwsFormatException);
    expect(() => formatRfc3339Utc(DateTime.utc(10000)), throwsFormatException);
  });

  test('ISO 8601 duration normalizes comma decimals to a dot', () {
    // Arrange / Act / Assert
    expect(IsoDuration.parse('PT0,5S').toString(), 'PT0.5S');
  });
}
