import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:diene_api_engine/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

/// META TIER — assert the asserter. Every assertion helper must FAIL on a
/// known-bad case and PASS on a known-good case.
void main() {
  final Result<int> ok = const Ok<int>(1);
  final Result<int> err = Err<int>(problemFixture(type: 'boom'));

  group('expectOk', () {
    test('passes on Ok, returns the value', () {
      expect(expectOk(ok), 1);
    });
    test('throws on Err', () {
      expect(() => expectOk(err), throwsA(isA<AssertionError>()));
    });
    test('the diagnostic names the Problem type and status', () {
      // A helper that throws an EMPTY diagnostic is barely better than no
      // helper: the consumer still has to go and find out what happened. So the
      // message content is asserted, not just the throw.
      expect(
        () => expectOk(err),
        throwsA(
          isA<AssertionError>().having(
            (AssertionError e) => e.message.toString(),
            'message',
            allOf(contains('boom'), contains('expected Ok')),
          ),
        ),
      );
    });
    test('the optional `because` reason is appended to the diagnostic', () {
      // `because` was never passed anywhere in this tier, so the branch that
      // composes it into the message had NEVER executed — the one uncovered line
      // in the whole helper. An unexercised diagnostic path is exactly where a
      // broken message hides until a consumer hits it.
      expect(
        () => expectOk(err, because: 'the backend must accept this token'),
        throwsA(
          isA<AssertionError>().having(
            (AssertionError e) => e.message.toString(),
            'message',
            contains('the backend must accept this token'),
          ),
        ),
      );
    });
  });

  group('expectErr', () {
    test('passes on Err, returns the problem', () {
      expect(expectErr(err).type, 'boom');
    });
    test('throws on Ok', () {
      expect(() => expectErr(ok), throwsA(isA<AssertionError>()));
    });
    test('the diagnostic shows the unexpected Ok value', () {
      expect(
        () => expectErr(ok),
        throwsA(
          isA<AssertionError>().having(
            (AssertionError e) => e.message.toString(),
            'message',
            allOf(contains('expected Err'), contains('1')),
          ),
        ),
      );
    });
    test('the optional `because` reason is appended to the diagnostic', () {
      expect(
        () => expectErr(ok, because: 'an absent token must fail closed'),
        throwsA(
          isA<AssertionError>().having(
            (AssertionError e) => e.message.toString(),
            'message',
            contains('an absent token must fail closed'),
          ),
        ),
      );
    });
  });

  group('expectProblemType', () {
    test('passes on a matching type', () {
      expect(expectProblemType(err, 'boom').type, 'boom');
    });
    test('throws on a mismatched type', () {
      expect(
        () => expectProblemType(err, 'other'),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('check', () {
    test('passes when true', () {
      expect(() => check(true, 'ok'), returnsNormally);
    });
    test('throws when false', () {
      expect(() => check(false, 'bad'), throwsA(isA<AssertionError>()));
    });
  });
}
