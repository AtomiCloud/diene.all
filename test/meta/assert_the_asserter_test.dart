import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:diene_api_engine/test_helper.dart';
import 'package:test/test.dart';

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
  });

  group('expectErr', () {
    test('passes on Err, returns the problem', () {
      expect(expectErr(err).type, 'boom');
    });
    test('throws on Ok', () {
      expect(() => expectErr(ok), throwsA(isA<AssertionError>()));
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
