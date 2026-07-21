import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:test/test.dart';

void main() {
  group('Result combinators', () {
    test('map transforms Ok and passes Err through', () {
      // Arrange
      final Result<int> ok = const Ok<int>(2);
      final Result<int> err = Err<int>(_p());

      // Act
      final Result<int> mappedOk = ok.map((int v) => v * 10);
      final Result<int> mappedErr = err.map((int v) => v * 10);

      // Assert
      expect(mappedOk, const Ok<int>(20));
      expect(mappedErr.isErr, isTrue);
    });

    test('mapErr transforms Err and passes Ok through', () {
      // Arrange
      final Result<int> err = Err<int>(_p(type: 'a'));

      // Act
      final Result<int> mapped =
          err.mapErr((Problem p) => p.copyWith(detail: 'wrapped'));

      // Assert
      expect(mapped.problem?.detail, 'wrapped');
      expect(const Ok<int>(1).mapErr((Problem p) => p).isOk, isTrue);
    });

    test('andThen chains only on Ok', () {
      // Arrange
      final Result<int> ok = const Ok<int>(3);

      // Act
      final Result<String> chained = ok.andThen((int v) => Ok<String>('n$v'));
      final Result<String> shortCircuit =
          Err<int>(_p()).andThen((int v) => Ok<String>('n$v'));

      // Assert
      expect(chained, const Ok<String>('n3'));
      expect(shortCircuit.isErr, isTrue);
    });

    test('fold and match collapse both arms', () {
      // Arrange / Act / Assert
      expect(
        const Ok<int>(5).fold(onSuccess: (int v) => v, onFailure: (_) => -1),
        5,
      );
      expect(
        Err<int>(_p()).match(ok: (int v) => v, err: (_) => -1),
        -1,
      );
    });

    test('unwrap family', () {
      expect(const Ok<int>(7).unwrap(), 7);
      expect(() => Err<int>(_p()).unwrap(), throwsStateError);
      expect(Err<int>(_p()).unwrapOr(9), 9);
      expect(Err<int>(_p()).unwrapOrElse((Problem p) => p.status), 400);
    });

    test('projections', () {
      expect(const Ok<int>(1).ok, 1);
      expect(const Ok<int>(1).problem, isNull);
      expect(Err<int>(_p()).ok, isNull);
      expect(Err<int>(_p()).problem.type, 'x');
    });
  });

  group('Problem wire form', () {
    test('round-trips through JSON', () {
      // Arrange
      final Problem original = Problem(
        type: 'urn:diene:problem:x',
        title: 'X',
        status: 418,
        detail: 'teapot',
        instance: '/pot',
        recoverable: true,
        data: const <String, Object?>{'k': 'v'},
      );

      // Act
      final Problem decoded = Problem.fromJson(original.toJson());

      // Assert
      expect(decoded.type, original.type);
      expect(decoded.status, 418);
      expect(decoded.recoverable, isTrue);
      expect(decoded.data['k'], 'v');
    });

    test('tolerates absent fields', () {
      final Problem decoded = Problem.fromJson(const <String, Object?>{});
      expect(decoded.type, 'about:blank');
      expect(decoded.status, 500);
    });
  });
}

Problem _p({String type = 'x', int status = 400}) =>
    Problem(type: type, title: 'T', status: status);
