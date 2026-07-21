import 'package:diene_core_utils/diene_core_utils.dart';
import 'package:test/test.dart';

void main() {
  const WireCodec codec = WireCodec();

  test('C0 temporal fixtures round-trip through canonical wire forms', () {
    // Arrange
    final WireDate date = WireDate(2026, 7, 21);
    final WireTime time = WireTime(1, 2, 3);
    final DateTime instant = DateTime.parse('2026-07-21T01:02:03.456Z');
    final IsoDuration duration = IsoDuration.parse('P1DT2H3M4.5S');
    final IanaTimezone timezone = IanaTimezone.parse('Asia/Singapore');

    // Act
    final List<Object> decoded = <Object>[
      codec.decodeDate(codec.encodeDate(date)),
      codec.decodeTime(codec.encodeTime(time)),
      codec.decodeInstant(codec.encodeInstant(instant)),
      codec.decodeDuration(codec.encodeDuration(duration)),
      codec.decodeTimezone(codec.encodeTimezone(timezone)),
    ];

    // Assert
    expect(decoded, <Object>[date, time, instant, duration, timezone]);
    expect(codec.encodeDate(date), '2026-07-21');
    expect(codec.encodeTime(time), '01:02:03');
    expect(codec.encodeInstant(instant), '2026-07-21T01:02:03.456Z');
    expect(codec.encodeDuration(duration), 'P1DT2H3M4.5S');
    expect(codec.encodeTimezone(timezone), 'Asia/Singapore');
    expect(date.hashCode, WireDate.parse('2026-07-21').hashCode);
    expect(time.hashCode, WireTime.parse('01:02:03').hashCode);
    expect(duration.hashCode, IsoDuration.parse('P1DT2H3M4.5S').hashCode);
    expect(timezone.hashCode, IanaTimezone.parse('Asia/Singapore').hashCode);
  });

  test('RFC 3339 formatter normalizes offsets to a UTC Z instant', () {
    // Arrange
    final DateTime offset = DateTime.parse('2026-07-21T09:02:03+08:00');

    // Act
    final String actual = formatRfc3339Utc(offset);

    // Assert
    expect(actual, '2026-07-21T01:02:03.000Z');
  });

  test('wire parsers reject non-canonical or semantically invalid forms', () {
    // Arrange
    final List<void Function()> invalid = <void Function()>[
      () => WireDate.parse('21-07-2026'),
      () => WireDate.parse('2026-02-30'),
      () => WireTime.parse('24:00:00'),
      () => parseRfc3339Utc('2026-07-21T01:02:03+00:00'),
      () => parseRfc3339Utc('2026-02-30T01:02:03Z'),
      () => IsoDuration.parse('10 minutes'),
      () => IanaTimezone.parse('UTC'),
      () => IanaTimezone.parse('+08:00'),
      () => IanaTimezone.parse('Area/../Location'),
    ];

    // Act / Assert
    for (final void Function() parse in invalid) {
      expect(parse, throwsFormatException);
    }
  });

  test('wire value constructors reject invalid component ranges', () {
    // Arrange / Act / Assert
    expect(() => WireDate(0, 1, 1), throwsFormatException);
    expect(() => WireTime(1, 60, 1), throwsFormatException);
    expect(() => formatRfc3339Utc(DateTime.utc(10000)), throwsFormatException);
    expect(IsoDuration.parse('PT0,5S').toString(), 'PT0.5S');
    expect(
      IanaTimezone.parse('America/Argentina/Buenos_Aires').toString(),
      'America/Argentina/Buenos_Aires',
    );
  });
}
