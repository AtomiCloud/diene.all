import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:diene_core_utils/c0_temporal.dart';
import 'package:diene_core_utils/diene_core_utils.dart'
    show
        IanaTimezone,
        IsoDuration,
        WireCodec,
        WireDate,
        WireTime,
        ianaTimeZoneRelease,
        isIanaTimeZone,
        normalizeRfc3339ToUtc,
        parseRfc3339Utc,
        wireDateGrammar,
        wireDurationGrammar,
        wireInstantGrammar,
        wireTimeGrammar,
        wireTimezoneGrammar;
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

/// C0 §1 temporal conformance, driven from the SHARED contract this package
/// owns and exports at `package:diene_core_utils/c0_temporal.dart`.
///
/// Release `c0-fixtures-r2` declares only the `config`, `identity`, `problem`,
/// and `result-wire` domains — there is no temporal case file to project — so
/// the vectors live in `c0TemporalContract`, whose provenance pins the C0 source
/// document AND the official IANA release. Downstream Dart-family packages drive
/// their own temporal conformance from the same value rather than restating
/// cases, so this suite is what keeps the family's single temporal contract
/// honest.
///
/// No host clock and no host IANA data is read anywhere below: every instant is
/// injected from the contract, and timezone membership resolves against the
/// vendored release baked into `isIanaTimeZone`.
void main() {
  const C0TemporalContract contract = c0TemporalContract;
  const WireCodec codec = WireCodec();

  group('contract provenance', () {
    test('the recorded digest authenticates the committed vectors', () {
      // Stale-fixture detection: any vector edit changes digestPayload, so the
      // recorded contentSha256 must be updated deliberately alongside it.
      final String actual = sha256
          .convert(utf8.encode(contract.digestPayload()))
          .toString();
      expect(
        actual,
        contract.provenance.contentSha256,
        reason:
            'temporal vectors changed without updating '
            'provenance.contentSha256 (expected $actual)',
      );
    });

    test(
      'provenance pins the C0 source and the IANA release actually baked in',
      () {
        expect(contract.provenance.contractVersion, '1');
        expect(contract.provenance.c0Section, 'C0 §1 Serialization');
        expect(contract.provenance.c0Source, 'goals/c0-contracts.md');
        expect(contract.provenance.ianaRelease, ianaTimeZoneRelease);
        expect(
          contract.provenance.ianaArchiveUrl,
          'https://data.iana.org/time-zones/releases/tzdata2026b.tar.gz',
        );
        expect(
          contract.provenance.ianaArchiveSha256,
          matches(RegExp(r'^[0-9a-f]{64}$')),
        );
      },
    );

    test('every vector list carries cases, so no group below is vacuous', () {
      final Map<String, C0Cases> domains = <String, C0Cases>{
        'dates': contract.dates,
        'times': contract.times,
        'durations': contract.durations,
        'timezones': contract.timezones,
      };
      domains.forEach((String name, C0Cases cases) {
        expect(cases.valid, isNotEmpty, reason: '$name has no valid cases');
        expect(cases.invalid, isNotEmpty, reason: '$name has no invalid cases');
      });
      expect(contract.instants, isNotEmpty);
      expect(contract.invalidInstants, isNotEmpty);
    });
  });

  group('C0 §1 calendar dates', () {
    test('every valid case round-trips through the canonical wire form', () {
      for (final String wire in contract.dates.valid) {
        final Result<WireDate> parsed = WireDate.parse(wire);
        expect(parsed.isOk, isTrue, reason: '$wire: ${_describe(parsed)}');
        expect(codec.encodeDate(parsed.unwrap()), wire);
        expect(codec.decodeDate(wire).unwrap(), parsed.unwrap());
      }
    });

    test('every invalid case is rejected as a Problem, never thrown', () {
      for (final String wire in contract.dates.invalid) {
        final Result<WireDate> parsed = WireDate.parse(wire);
        expect(parsed.isErr, isTrue, reason: '$wire was accepted');
        _expectWireProblem(parsed, wireDateGrammar, wire, exactGrammar: false);
      }
    });
  });

  group('C0 §1 wall-clock times', () {
    test('every valid case round-trips through the canonical wire form', () {
      for (final String wire in contract.times.valid) {
        final Result<WireTime> parsed = WireTime.parse(wire);
        expect(parsed.isOk, isTrue, reason: '$wire: ${_describe(parsed)}');
        expect(codec.encodeTime(parsed.unwrap()), wire);
        expect(codec.decodeTime(wire).unwrap(), parsed.unwrap());
      }
    });

    test('every invalid case is rejected as a Problem', () {
      for (final String wire in contract.times.invalid) {
        final Result<WireTime> parsed = WireTime.parse(wire);
        expect(parsed.isErr, isTrue, reason: '$wire was accepted');
        _expectWireProblem(parsed, wireTimeGrammar, wire, exactGrammar: false);
      }
    });
  });

  group('C0 §1 durations', () {
    test('every valid designation is preserved without lossy conversion', () {
      for (final String wire in contract.durations.valid) {
        final Result<IsoDuration> parsed = IsoDuration.parse(wire);
        expect(parsed.isOk, isTrue, reason: '$wire: ${_describe(parsed)}');
        expect(codec.encodeDuration(parsed.unwrap()), wire);
      }
    });

    test('every invalid designation is rejected as a Problem', () {
      for (final String wire in contract.durations.invalid) {
        final Result<IsoDuration> parsed = IsoDuration.parse(wire);
        expect(parsed.isErr, isTrue, reason: '$wire was accepted');
        _expectWireProblem(parsed, wireDurationGrammar, wire);
      }
    });
  });

  group('C0 §1 IANA timezone identifiers', () {
    test('the contract settles legacy ids and aliases, not host membership', () {
      // The contract deliberately fixes EST/GMT (genuine IANA entries) as valid
      // and PST (an abbreviation only) as invalid, so the answer does not depend
      // on whichever tzdata the host happens to carry.
      expect(contract.timezones.valid, contains('EST'));
      expect(contract.timezones.valid, contains('GMT'));
      expect(contract.timezones.valid, contains('US/Eastern'));
      expect(contract.timezones.invalid, contains('PST'));

      for (final String id in contract.timezones.valid) {
        final Result<IanaTimezone> parsed = IanaTimezone.parse(id);
        expect(parsed.isOk, isTrue, reason: '$id: ${_describe(parsed)}');
        expect(codec.encodeTimezone(parsed.unwrap()), id);
        expect(isIanaTimeZone(id), isTrue);
      }
    });

    test('offsets, wrong case, traversal, and unknown names are rejected', () {
      for (final String id in contract.timezones.invalid) {
        final Result<IanaTimezone> parsed = IanaTimezone.parse(id);
        expect(parsed.isErr, isTrue, reason: '$id was accepted');
        _expectWireProblem(parsed, wireTimezoneGrammar, id);
        expect(isIanaTimeZone(id), isFalse);
      }
    });
  });

  group('C0 §1 instants', () {
    test('every vector normalises to its canonical UTC spelling', () {
      for (final C0InstantVector vector in contract.instants) {
        final Result<String> normalized = normalizeRfc3339ToUtc(vector.input);
        expect(
          normalized.isOk,
          isTrue,
          reason: '${vector.input}: ${_describe(normalized)}',
        );
        expect(normalized.unwrap(), vector.canonicalUtc);

        // The canonical spelling must itself be accepted by the STRICT parser,
        // so normalisation is idempotent at the wire boundary.
        final Result<DateTime> reparsed = parseRfc3339Utc(vector.canonicalUtc);
        expect(reparsed.isOk, isTrue, reason: _describe(reparsed));
        expect(reparsed.unwrap().isUtc, isTrue);
        expect(
          codec.encodeInstant(reparsed.unwrap()).unwrap(),
          vector.canonicalUtc,
        );
      }
    });

    test('the strict parser rejects every non-canonical spelling', () {
      // This is the whole point of the surface: +00:00 denotes the SAME instant
      // as Z and is still rejected, because C0 fixes ONE spelling so two
      // services can compare wire bytes.
      expect(contract.invalidInstants, contains('2026-07-21T01:02:03+00:00'));
      for (final String wire in contract.invalidInstants) {
        final Result<DateTime> parsed = parseRfc3339Utc(wire);
        expect(parsed.isErr, isTrue, reason: '$wire was accepted');
        _expectWireProblem(
          parsed,
          wireInstantGrammar,
          wire,
          exactGrammar: false,
        );
      }
    });

    test(
      'an offset-carrying instant is accepted only at the ingress helper',
      () {
        const String offset = '2026-07-21T09:02:03+08:00';
        expect(parseRfc3339Utc(offset).isErr, isTrue);
        expect(codec.decodeInstant(offset).isErr, isTrue);
        expect(
          codec.normalizeInstant(offset).unwrap(),
          '2026-07-21T01:02:03.000Z',
        );
      },
    );
  });
}

/// The grammars a temporal rejection is allowed to name.
///
/// A well-shaped instant whose DATE or TIME components are impossible is
/// rejected by the component grammar, not the instant grammar — that is more
/// useful to a caller than a blanket "not an instant". [_expectWireProblem]
/// therefore accepts any declared grammar unless the caller pins one, while
/// still requiring the envelope to name the value the caller actually passed.
const Set<String> _declaredGrammars = <String>{
  wireDateGrammar,
  wireTimeGrammar,
  wireInstantGrammar,
  wireDurationGrammar,
  wireTimezoneGrammar,
};

void _expectWireProblem(
  Result<Object?> result,
  String expectedGrammar,
  String rejectedValue, {
  bool exactGrammar = true,
}) {
  final Problem problem = result.unwrapErr();
  expect(problem.status, 400);
  expect(problem.recoverable, isFalse);
  final Map<String, Object?> data = problem.data;
  expect(data['util'], 'wire');
  expect(data['code'], 'invalid_format');
  if (exactGrammar) {
    expect(data['expected'], expectedGrammar);
    expect(problem.title, 'expected $expectedGrammar');
  } else {
    expect(
      _declaredGrammars,
      contains(data['expected']),
      reason: 'rejection named an undeclared grammar: ${data['expected']}',
    );
    expect(problem.title, 'expected ${data['expected']}');
  }
  // The rejected value must be what the CALLER passed, not a re-rendering of
  // parsed components: a re-rendering silently changes the diagnostic (and hid a
  // real defect here until the conformance vectors caught it).
  expect(data['value'], rejectedValue);
  // C0 §2: the type URI is minted by the ONE builder, so it must be the shape
  // that builder produces rather than a hand-formatted string.
  expect(problem.type, contains('/v1/'));
  expect(problem.type, endsWith('wire_invalid_format'));
}

String _describe(Result<Object?> result) => result.match(
  ok: (Object? value) => 'ok($value)',
  err: (Problem problem) => 'err(${problem.title}: ${problem.detail})',
);
