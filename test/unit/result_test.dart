import 'package:diene_auth_engine/diene_auth_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Result', () {
    test('map transforms success and leaves failure untouched', () {
      // Arrange
      const Result<int> ok = Success<int>(2);
      const Result<int> err = Failure<int>(
        Problem(type: 't', title: 'x', status: 400),
      );

      // Act
      final Result<int> mapped = ok.map((int v) => v * 3);
      final Result<int> mappedErr = err.map((int v) => v * 3);

      // Assert
      expect((mapped as Success<int>).value, 6);
      expect(mappedErr, isA<Failure<int>>());
    });

    test('andThen chains only on success', () {
      // Arrange
      const Result<int> ok = Success<int>(4);

      // Act
      final Result<String> chained = ok.andThen(
        (int v) => Success<String>('n$v'),
      );

      // Assert
      expect((chained as Success<String>).value, 'n4');
    });

    test('mapErr rewrites the problem', () {
      // Arrange
      const Result<int> err = Failure<int>(
        Problem(type: 't', title: 'x', status: 400),
      );

      // Act
      final Result<int> mapped = err.mapErr(
        (Problem p) => Problem(type: p.type, title: 'y', status: 401),
      );

      // Assert
      expect(mapped.problemOrNull?.status, 401);
    });

    test('unwrapOr / valueOrNull / match', () {
      // Arrange
      const Result<int> ok = Success<int>(9);
      const Result<int> err = Failure<int>(
        Problem(type: 't', title: 'x', status: 400),
      );

      // Assert
      expect(ok.unwrapOr(0), 9);
      expect(err.unwrapOr(0), 0);
      expect(ok.valueOrNull, 9);
      expect(err.valueOrNull, isNull);
      expect(ok.match(onSuccess: (_) => 'a', onFailure: (_) => 'b'), 'a');
    });
  });

  group('Option', () {
    test('of maps null to None and value to Some', () {
      // Assert
      expect(Option<int>.of(null).isNone, isTrue);
      expect(Option<int>.of(5).isSome, isTrue);
      expect(Option<int>.of(5).unwrapOr(0), 5);
      expect(Option<int>.none().unwrapOr(-1), -1);
    });
  });

  group('Problem', () {
    test('round-trips through JSON', () {
      // Arrange
      const Problem problem = Problem(
        type: 'urn:x',
        title: 'boom',
        status: 503,
        detail: 'why',
        recoverable: true,
        data: <String, Object?>{'k': 1},
      );

      // Act
      final Problem parsed = Problem.fromJson(problem.toJson());

      // Assert
      expect(parsed, problem);
      expect(parsed.data['k'], 1);
    });

    test('type URI is built in one place', () {
      // Act
      final String uri = problemTypeUri(
        base: 'https://p.example/',
        landscape: 'lapras',
        platform: 'lithium',
        service: 'api',
        module: 'auth',
        version: '1',
        id: 'boom',
      );

      // Assert
      expect(uri, 'https://p.example/lapras/lithium/api/auth/1/boom');
    });
  });
}
