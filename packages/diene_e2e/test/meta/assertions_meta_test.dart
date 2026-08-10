import 'package:diene_e2e/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

/// Assert-the-asserter: every assertion helper must PASS on a known-good input
/// and THROW [JourneyAssertionError] on a known-bad one.
void main() {
  JourneyResult passing() => const JourneyResult(<JourneyStepResult>[
    JourneyStepResult(name: 'a', ok: true),
  ]);
  JourneyResult failing() => const JourneyResult(<JourneyStepResult>[
    JourneyStepResult(name: 'a', ok: true),
    JourneyStepResult(name: 'b', ok: false, detail: 'boom'),
  ]);

  group('expectJourneyOk', () {
    test('passes on a fully-passing journey', () {
      expect(() => expectJourneyOk(passing()), returnsNormally);
    });
    test('throws on a failing journey and names the failing step', () {
      expect(
        () => expectJourneyOk(failing()),
        throwsA(
          isA<JourneyAssertionError>().having(
            (JourneyAssertionError e) => e.message,
            'message',
            contains("step 'b'"),
          ),
        ),
      );
    });
  });

  group('expectJourneyFailedAt', () {
    test('passes when the named step is the failure', () {
      expect(() => expectJourneyFailedAt(failing(), 'b'), returnsNormally);
    });
    test('throws when the journey passed', () {
      expect(
        () => expectJourneyFailedAt(passing(), 'b'),
        throwsA(isA<JourneyAssertionError>()),
      );
    });
    test('throws when a different step failed', () {
      expect(
        () => expectJourneyFailedAt(failing(), 'a'),
        throwsA(isA<JourneyAssertionError>()),
      );
    });
  });

  group('expectEquals', () {
    test('passes on equal values', () {
      expect(() => expectEquals(1, 1), returnsNormally);
    });
    test('throws on unequal values with reason', () {
      expect(
        () => expectEquals(1, 2, reason: 'counts'),
        throwsA(
          isA<JourneyAssertionError>().having(
            (JourneyAssertionError e) => e.message,
            'message',
            contains('counts'),
          ),
        ),
      );
    });
  });

  group('expectTrue', () {
    test('passes when condition holds', () {
      expect(() => expectTrue(true, 'x'), returnsNormally);
    });
    test('throws with the message when condition fails', () {
      expect(
        () => expectTrue(false, 'the message'),
        throwsA(
          isA<JourneyAssertionError>().having(
            (JourneyAssertionError e) => e.toString(),
            'toString',
            contains('the message'),
          ),
        ),
      );
    });
  });
}
