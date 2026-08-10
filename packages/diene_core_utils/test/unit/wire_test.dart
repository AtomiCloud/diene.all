import 'package:diene_core_utils/diene_core_utils.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

/// Unit coverage for the C0 §1 wire codecs.
///
/// The normative vectors are asserted in `test/conformance/c0_temporal_test.dart`
/// against the shared contract; this suite covers the component-level edges that
/// contract does not enumerate (component constructors, padding, equality, the
/// codec facade, and the normalisation ingress).
void main() {
  const WireCodec codec = WireCodec();

  group('WireDate', () {
    test('of() validates the components', () {
      expect(WireDate.of(2026, 7, 26).unwrap().toString(), '2026-07-26');
      expect(WireDate.of(2000, 2, 29).unwrap().toString(), '2000-02-29');
    });

    test('of() rejects an impossible calendar date', () {
      for (final List<int> parts in <List<int>>[
        <int>[2026, 2, 30],
        <int>[2026, 13, 1],
        <int>[2026, 0, 1],
        <int>[2026, 1, 32],
        <int>[2026, 1, 0],
        <int>[1900, 2, 29],
      ]) {
        final Result<WireDate> date = WireDate.of(parts[0], parts[1], parts[2]);
        expect(date.isErr, isTrue, reason: '$parts was accepted');
        expect(date.unwrapErr().data['util'], 'wire');
      }
    });

    test('of() rejects a year outside 1..9999', () {
      expect(WireDate.of(0, 1, 1).isErr, isTrue);
      expect(WireDate.of(-1, 1, 1).isErr, isTrue);
      expect(WireDate.of(10000, 1, 1).isErr, isTrue);
      expect(WireDate.of(1, 1, 1).unwrap().toString(), '0001-01-01');
      expect(WireDate.of(9999, 12, 31).unwrap().toString(), '9999-12-31');
    });

    test('components are exposed and zero-padded on the wire', () {
      final WireDate date = WireDate.of(7, 1, 2).unwrap();
      expect(date.year, 7);
      expect(date.month, 1);
      expect(date.day, 2);
      expect(date.toString(), '0007-01-02');
    });

    test('equality and hashCode are structural', () {
      final WireDate a = WireDate.parse('2026-07-26').unwrap();
      final WireDate b = WireDate.of(2026, 7, 26).unwrap();
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == WireDate.of(2026, 7, 27).unwrap(), isFalse);
      expect(a == WireDate.of(2026, 8, 26).unwrap(), isFalse);
      expect(a == WireDate.of(2027, 7, 26).unwrap(), isFalse);
      // ignore: unrelated_type_equality_checks
      expect(a == '2026-07-26', isFalse);
    });

    test('parse() rejects a shape mismatch before validating components', () {
      final Result<WireDate> parsed = WireDate.parse('2026-7-1');
      expect(parsed.unwrapErr().data['expected'], wireDateGrammar);
      expect(parsed.unwrapErr().data['operation'], 'WireDate.parse');
    });
  });

  group('WireTime', () {
    test('of() validates the components', () {
      expect(WireTime.of(0, 0, 0).unwrap().toString(), '00:00:00');
      expect(WireTime.of(23, 59, 59).unwrap().toString(), '23:59:59');
    });

    test('of() rejects out-of-range components', () {
      for (final List<int> parts in <List<int>>[
        <int>[24, 0, 0],
        <int>[-1, 0, 0],
        <int>[0, 60, 0],
        <int>[0, -1, 0],
        <int>[0, 0, 60],
        <int>[0, 0, -1],
      ]) {
        expect(
          WireTime.of(parts[0], parts[1], parts[2]).isErr,
          isTrue,
          reason: '$parts was accepted',
        );
      }
    });

    test('there is no leap second on the wire', () {
      expect(WireTime.parse('23:59:60').isErr, isTrue);
    });

    test('components are exposed and equality is structural', () {
      final WireTime time = WireTime.of(1, 2, 3).unwrap();
      expect(<int>[time.hour, time.minute, time.second], <int>[1, 2, 3]);
      expect(time, WireTime.parse('01:02:03').unwrap());
      expect(time.hashCode, WireTime.parse('01:02:03').unwrap().hashCode);
      expect(time == WireTime.of(1, 2, 4).unwrap(), isFalse);
      expect(time == WireTime.of(1, 3, 3).unwrap(), isFalse);
      expect(time == WireTime.of(2, 2, 3).unwrap(), isFalse);
      // ignore: unrelated_type_equality_checks
      expect(time == 3, isFalse);
    });
  });

  group('IsoDuration', () {
    test('a decimal comma is normalised to a point', () {
      expect(IsoDuration.parse('PT0,5S').unwrap().value, 'PT0.5S');
      expect(IsoDuration.parse('P1DT2,5H').unwrap().toString(), 'P1DT2.5H');
    });

    test('calendar units are preserved rather than converted', () {
      // Y/M/W have no fixed length, so the designation is kept verbatim.
      expect(IsoDuration.parse('P1Y2M3W4D').unwrap().value, 'P1Y2M3W4D');
    });

    test('equality is structural over the normalised value', () {
      final IsoDuration comma = IsoDuration.parse('PT0,5S').unwrap();
      final IsoDuration point = IsoDuration.parse('PT0.5S').unwrap();
      expect(comma, point);
      expect(comma.hashCode, point.hashCode);
      expect(comma == IsoDuration.parse('PT1S').unwrap(), isFalse);
      // ignore: unrelated_type_equality_checks
      expect(comma == 'PT0.5S', isFalse);
    });

    test('a designation with no components is rejected', () {
      for (final String bad in <String>['P', 'PT', 'PW', '', 'T1H', '1DT2H']) {
        expect(
          IsoDuration.parse(bad).isErr,
          isTrue,
          reason: '$bad was accepted',
        );
      }
    });
  });

  group('IanaTimezone', () {
    test('membership comes from the vendored release, not the host', () {
      expect(
        IanaTimezone.parse('Asia/Singapore').unwrap().value,
        'Asia/Singapore',
      );
      expect(
        IanaTimezone.parse(
          'America/Argentina/Buenos_Aires',
        ).unwrap().toString(),
        'America/Argentina/Buenos_Aires',
      );
      expect(IanaTimezone.parse('Etc/UTC').isOk, isTrue);
      expect(IanaTimezone.parse('UTC').isOk, isTrue);
    });

    test('equality is structural', () {
      final IanaTimezone a = IanaTimezone.parse('UTC').unwrap();
      expect(a, IanaTimezone.parse('UTC').unwrap());
      expect(a.hashCode, IanaTimezone.parse('UTC').unwrap().hashCode);
      expect(a == IanaTimezone.parse('Etc/UTC').unwrap(), isFalse);
      // ignore: unrelated_type_equality_checks
      expect(a == 'UTC', isFalse);
    });

    test('path traversal is rejected as a plain non-member', () {
      expect(IanaTimezone.parse('Area/../Location').isErr, isTrue);
      expect(IanaTimezone.parse('../../etc/passwd').isErr, isTrue);
    });
  });

  group('formatRfc3339Utc', () {
    test('a local DateTime is normalised to UTC rather than rejected', () {
      final DateTime local = DateTime.utc(2026, 7, 26, 1, 2, 3).toLocal();
      expect(formatRfc3339Utc(local).unwrap(), '2026-07-26T01:02:03.000Z');
    });

    test('sub-second precision survives', () {
      expect(
        formatRfc3339Utc(DateTime.utc(2026, 7, 26, 1, 2, 3, 456)).unwrap(),
        '2026-07-26T01:02:03.456Z',
      );
    });

    test('a year with no RFC 3339 representation is rejected', () {
      expect(formatRfc3339Utc(DateTime.utc(0, 1, 1)).isErr, isTrue);
      expect(formatRfc3339Utc(DateTime.utc(-1, 1, 1)).isErr, isTrue);
      expect(formatRfc3339Utc(DateTime.utc(10000, 1, 1)).isErr, isTrue);
    });
  });

  group('normalizeRfc3339ToUtc', () {
    test('an offset instant becomes the canonical Z form', () {
      expect(
        normalizeRfc3339ToUtc('2026-07-26T09:02:03+08:00').unwrap(),
        '2026-07-26T01:02:03.000Z',
      );
      expect(
        normalizeRfc3339ToUtc('2026-07-25T20:02:03-05:00').unwrap(),
        '2026-07-26T01:02:03.000Z',
      );
      expect(
        normalizeRfc3339ToUtc('2026-07-26T01:02:03+0000').unwrap(),
        '2026-07-26T01:02:03.000Z',
      );
    });

    test(
      'an already-canonical instant is idempotent, including lowercase z',
      () {
        expect(
          normalizeRfc3339ToUtc('2026-07-26T01:02:03Z').unwrap(),
          '2026-07-26T01:02:03.000Z',
        );
        expect(
          normalizeRfc3339ToUtc('2026-07-26T01:02:03z').unwrap(),
          '2026-07-26T01:02:03.000Z',
        );
      },
    );

    test('an instant with NO zone designator is rejected', () {
      // A zone-less local timestamp is exactly the bespoke shape C0 kills: it
      // means nothing without the writer's zone.
      final Result<String> normalized = normalizeRfc3339ToUtc(
        '2026-07-26T01:02:03',
      );
      expect(normalized.isErr, isTrue);
      expect(normalized.unwrapErr().data['operation'], 'normalizeRfc3339ToUtc');
    });

    test('unparseable input is rejected', () {
      expect(normalizeRfc3339ToUtc('not-a-date').isErr, isTrue);
      expect(normalizeRfc3339ToUtc('').isErr, isTrue);
    });

    test('a normalised value out of RFC 3339 range still fails', () {
      expect(normalizeRfc3339ToUtc('0000-01-01T00:00:00Z').isErr, isTrue);
    });
  });

  group('parseRfc3339Utc', () {
    test('the returned DateTime is always UTC', () {
      final DateTime parsed = parseRfc3339Utc('2026-07-26T01:02:03Z').unwrap();
      expect(parsed.isUtc, isTrue);
      expect(parsed, DateTime.utc(2026, 7, 26, 1, 2, 3));
    });

    test('an invalid TIME inside a well-shaped instant is rejected', () {
      final Result<DateTime> parsed = parseRfc3339Utc('2026-07-26T24:00:00Z');
      expect(parsed.isErr, isTrue);
      expect(parsed.unwrapErr().data['expected'], wireTimeGrammar);
    });

    test('an invalid DATE inside a well-shaped instant is rejected', () {
      final Result<DateTime> parsed = parseRfc3339Utc('2026-02-30T01:02:03Z');
      expect(parsed.isErr, isTrue);
      expect(parsed.unwrapErr().data['expected'], wireDateGrammar);
    });
  });

  group('WireCodec facade', () {
    test('every member delegates to the documented surface', () {
      final WireDate date = WireDate.of(2026, 7, 26).unwrap();
      final WireTime time = WireTime.of(1, 2, 3).unwrap();
      final IsoDuration duration = IsoDuration.parse('P1W').unwrap();
      final IanaTimezone zone = IanaTimezone.parse('Asia/Singapore').unwrap();

      expect(codec.encodeDate(date), '2026-07-26');
      expect(codec.decodeDate('2026-07-26').unwrap(), date);
      expect(codec.encodeTime(time), '01:02:03');
      expect(codec.decodeTime('01:02:03').unwrap(), time);
      expect(codec.encodeDuration(duration), 'P1W');
      expect(codec.decodeDuration('P1W').unwrap(), duration);
      expect(codec.encodeTimezone(zone), 'Asia/Singapore');
      expect(codec.decodeTimezone('Asia/Singapore').unwrap(), zone);
      expect(
        codec.encodeInstant(DateTime.utc(2026, 7, 26, 1, 2, 3)).unwrap(),
        '2026-07-26T01:02:03.000Z',
      );
      expect(
        codec.decodeInstant('2026-07-26T01:02:03Z').unwrap(),
        DateTime.utc(2026, 7, 26, 1, 2, 3),
      );
      expect(
        codec.normalizeInstant('2026-07-26T09:02:03+08:00').unwrap(),
        '2026-07-26T01:02:03.000Z',
      );
    });

    test('failures surface through the facade unchanged', () {
      expect(codec.decodeDate('nope').isErr, isTrue);
      expect(codec.decodeTime('nope').isErr, isTrue);
      expect(codec.decodeDuration('nope').isErr, isTrue);
      expect(codec.decodeTimezone('PST').isErr, isTrue);
      expect(codec.decodeInstant('nope').isErr, isTrue);
      expect(codec.normalizeInstant('nope').isErr, isTrue);
      expect(codec.encodeInstant(DateTime.utc(0, 1, 1)).isErr, isTrue);
    });

    test('the facade is a const value, so injecting it costs nothing', () {
      expect(const WireCodec(), isA<WireCodec>());
    });
  });

  group('grammar constants', () {
    test('each names its own domain and is used in that domain only', () {
      final Map<String, Result<Object?>> byGrammar = <String, Result<Object?>>{
        wireDateGrammar: WireDate.parse('nope'),
        wireTimeGrammar: WireTime.parse('nope'),
        wireDurationGrammar: IsoDuration.parse('nope'),
        wireTimezoneGrammar: IanaTimezone.parse('nope'),
        wireInstantGrammar: parseRfc3339Utc('nope'),
      };
      expect(byGrammar.keys.toSet(), hasLength(5), reason: 'grammars collide');
      byGrammar.forEach((String grammar, Result<Object?> result) {
        expect(result.unwrapErr().data["expected"], grammar);
      });
    });
  });
}
