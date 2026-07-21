import 'package:diene_result/diene_result.dart';
import 'package:diene_result/test_helper.dart';
import 'package:test/test.dart';

void main() {
  final Problem problem = Problem(
    type: 'about:blank',
    title: 'Known failure',
    status: 400,
  );

  group('Result TestHelper assertions', () {
    test('expectOk passes and unwraps a known-good Ok', () {
      // Arrange
      const Result<int> actual = Result<int>.ok(42);

      // Act
      final int value = expectOk(actual);

      // Assert
      expect(value, 42);
    });

    test('expectOk fails loudly on a known-bad Err', () {
      // Arrange
      final Result<int> actual = Result<int>.err(problem);

      // Act
      Object? failure;
      try {
        expectOk(actual);
      } on Object catch (error) {
        failure = error;
      }

      // Assert
      expect(failure, isA<TestHelperFailure>());
      expect(failure.toString(), contains('Expected Ok, got Err'));
      expect(failure.toString(), contains('Known failure'));
    });

    test('expectErr passes and unwraps a known-good Err', () {
      // Arrange
      final Result<int> actual = Result<int>.err(problem);

      // Act
      final Problem value = expectErr(actual);

      // Assert
      expect(value, same(problem));
    });

    test('expectErr fails loudly on a known-bad Ok', () {
      // Arrange
      const Result<int> actual = Result<int>.ok(42);

      // Act
      Object? failure;
      try {
        expectErr(actual);
      } on Object catch (error) {
        failure = error;
      }

      // Assert
      expect(failure, isA<TestHelperFailure>());
      expect(failure.toString(), contains('Expected Err, got Ok carrying 42'));
    });
  });

  group('Option TestHelper assertions', () {
    test('expectSome passes and unwraps a known-good Some', () {
      // Arrange
      const Option<String> actual = Option<String>.some('lapras');

      // Act
      final String value = expectSome(actual);

      // Assert
      expect(value, 'lapras');
    });

    test('expectSome fails loudly on a known-bad None', () {
      // Arrange
      const Option<String> actual = Option<String>.none();

      // Act
      Object? failure;
      try {
        expectSome(actual);
      } on Object catch (error) {
        failure = error;
      }

      // Assert
      expect(failure, isA<TestHelperFailure>());
      expect(failure.toString(), contains('Expected Some, got None'));
    });

    test('expectNone passes on a known-good None', () {
      // Arrange
      const Option<String> actual = Option<String>.none();

      // Act
      expectNone(actual);

      // Assert
      expect(actual.isNone, isTrue);
    });

    test('expectNone fails loudly on a known-bad Some', () {
      // Arrange
      const Option<String> actual = Option<String>.some('lapras');

      // Act
      Object? failure;
      try {
        expectNone(actual);
      } on Object catch (error) {
        failure = error;
      }

      // Assert
      expect(failure, isA<TestHelperFailure>());
      expect(
        failure.toString(),
        contains('Expected None, got Some carrying lapras'),
      );
    });
  });
}
