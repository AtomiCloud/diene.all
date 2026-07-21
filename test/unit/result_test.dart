import 'dart:async';

import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

void main() {
  final Problem problem = Problem(
    type: 'https://errors.example/docs/lapras/shop/cart/checkout/v1/invalid',
    title: 'Invalid cart',
    status: 422,
    detail: 'The cart cannot be checked out.',
    instance: 'urn:request:result-test',
    recoverable: true,
    data: const <String, Object?>{'cartId': 'cart-1'},
  );

  group('Result', () {
    test(
      'constructors expose predicates, matching, native values, and text',
      () {
        // Arrange
        const Result<int> ok = Result<int>.ok(21);
        final Result<int> err = Result<int>.err(problem);

        // Act
        final String okMatch = ok.match(
          ok: (int value) => 'ok:$value',
          err: (Problem value) => 'err:${value.status}',
        );
        final String errMatch = err.match(
          ok: (int value) => 'ok:$value',
          err: (Problem value) => 'err:${value.status}',
        );

        // Assert
        expect(ok.isOk, isTrue);
        expect(ok.isErr, isFalse);
        expect(err.isOk, isFalse);
        expect(err.isErr, isTrue);
        expect(okMatch, 'ok:21');
        expect(errMatch, 'err:422');
        expect(ok.native(), 21);
        expect(err.native(), same(problem));
        expect(ok.toString(), 'Ok(21)');
        expect(err.toString(), contains('Err(Problem('));
      },
    );

    test('map, mapErr, and andThen transform only their owning channel', () {
      // Arrange
      const Result<int> ok = Result<int>.ok(21);
      final Result<int> err = Result<int>.err(problem);
      final Problem mappedProblem = Problem(
        type: problem.type,
        title: 'Mapped',
        status: 400,
      );

      // Act
      final Result<int> mapped = ok.map((int value) => value * 2);
      final Result<int> skippedMap = err.map((int value) => value * 2);
      final Result<int> mappedErr = err.mapErr((Problem _) => mappedProblem);
      final Result<int> skippedMapErr = ok.mapErr((Problem _) => mappedProblem);
      final Result<String> chained = ok.andThen(
        (int value) => Result<String>.ok('$value!'),
      );
      final Result<String> skippedChain = err.andThen(
        (int value) => Result<String>.ok('$value!'),
      );

      // Assert
      expect(mapped.unwrap(), 42);
      expect(skippedMap.unwrapErr(), same(problem));
      expect(mappedErr.unwrapErr(), same(mappedProblem));
      expect(skippedMapErr.unwrap(), 21);
      expect(chained.unwrap(), '21!');
      expect(skippedChain.unwrapErr(), same(problem));
    });

    test('callbacks propagate exceptions unless exec explicitly maps them', () {
      // Arrange
      const Result<int> ok = Result<int>.ok(21);
      final Result<int> err = Result<int>.err(problem);
      var sideEffectTotal = 0;

      // Act
      final Result<int> runResult = ok.run(
        (int value) => sideEffectTotal += value,
      );
      final Result<int> skippedRun = err.run(
        (int value) => sideEffectTotal += value,
      );
      final Result<int> execResult = ok.exec(
        (int _) => throw StateError('boom'),
        onException: (Object error, StackTrace _) =>
            Problem(type: 'about:blank', title: error.toString(), status: 500),
      );
      final Result<int> skippedExec = err.exec(
        (int _) => throw StateError('unreachable'),
        onException: (Object error, StackTrace _) =>
            Problem(type: 'about:blank', title: error.toString(), status: 500),
      );

      // Assert
      expect(runResult, same(ok));
      expect(skippedRun, same(err));
      expect(sideEffectTotal, 21);
      expect(execResult.unwrapErr().title, contains('boom'));
      expect(skippedExec, same(err));
      expect(
        () => ok.map<int>((int _) => throw StateError('poison')),
        throwsStateError,
      );
    });

    test('unwrap family returns values, fallbacks, and rich misuse errors', () {
      // Arrange
      const Result<int> ok = Result<int>.ok(21);
      final Result<int> err = Result<int>.err(problem);

      // Act
      final int okFallback = ok.unwrapOr(0);
      final int errFallback = err.unwrapOr(0);
      final int okComputed = ok.unwrapOrElse((Problem _) => 1);
      final int errComputed = err.unwrapOrElse((Problem value) => value.status);

      // Assert
      expect(ok.unwrap(), 21);
      expect(err.unwrapErr(), same(problem));
      expect(okFallback, 21);
      expect(errFallback, 0);
      expect(okComputed, 21);
      expect(errComputed, 422);
      expect(
        () => err.unwrap(),
        throwsA(
          isA<UnwrapError>()
              .having(
                (UnwrapError value) => value.monad,
                'monad',
                MonadKind.result,
              )
              .having((UnwrapError value) => value.expected, 'expected', 'Ok')
              .having((UnwrapError value) => value.actual, 'actual', 'Err')
              .having((UnwrapError value) => value.payload, 'payload', problem)
              .having(
                (UnwrapError value) => value.toString(),
                'text',
                contains('Err'),
              ),
        ),
      );
      expect(
        () => ok.unwrapErr(),
        throwsA(
          isA<UnwrapError>()
              .having((UnwrapError value) => value.expected, 'expected', 'Err')
              .having((UnwrapError value) => value.actual, 'actual', 'Ok')
              .having((UnwrapError value) => value.payload, 'payload', 21),
        ),
      );
    });

    test('ok and err project each channel to Option', () {
      // Arrange
      const Result<int> ok = Result<int>.ok(21);
      final Result<int> err = Result<int>.err(problem);

      // Act
      final Option<int> okValue = ok.ok();
      final Option<Problem> okProblem = ok.err();
      final Option<int> errValue = err.ok();
      final Option<Problem> errProblem = err.err();

      // Assert
      expect(okValue.unwrap(), 21);
      expect(okProblem.isNone, isTrue);
      expect(errValue.isNone, isTrue);
      expect(errProblem.unwrap(), same(problem));
    });

    test('serial encodes custom ok values and canonical problem errors', () {
      // Arrange
      const Result<int> ok = Result<int>.ok(21);
      final Result<int> err = Result<int>.err(problem);

      // Act
      final ResultSerial okWire = ok.serial(
        encodeOk: (int value) => <String, Object?>{'value': value},
      );
      final ResultSerial errWire = err.serial();
      final Result<int> decodedOk = Result<int>.fromSerial(
        okWire,
        decodeOk: (Object? value) =>
            (value! as Map<Object?, Object?>)['value']! as int,
      );
      final Result<int> decodedErr = Result<int>.fromSerial(
        errWire,
        decodeOk: (Object? value) => value! as int,
      );
      final Result<int> customDecodedErr = Result<int>.fromSerial(
        <Object?>['err', 'custom'],
        decodeOk: (Object? value) => value! as int,
        decodeErr: (Object? value) =>
            Problem(type: 'about:blank', title: value! as String, status: 500),
      );
      final Result<int> minimalDecodedErr = Result<int>.fromSerial(<Object?>[
        'err',
        <String, Object?>{
          'type': 'about:blank',
          'title': 'Minimal',
          'status': 500,
        },
      ], decodeOk: (Object? value) => value! as int);

      // Assert
      expect(okWire, <Object?>[
        'ok',
        <String, Object?>{'value': 21},
      ]);
      expect(errWire.first, 'err');
      expect(decodedOk.unwrap(), 21);
      expect(decodedErr.unwrapErr().toJson(), problem.toJson());
      expect(customDecodedErr.unwrapErr().title, 'custom');
      expect(minimalDecodedErr.unwrapErr().data, isEmpty);
      expect(() => okWire.add(1), throwsUnsupportedError);
    });

    test('malformed Result wire values fail before decoding payloads', () {
      // Arrange
      final List<ResultSerial> malformed = <ResultSerial>[
        <Object?>['ok'],
        <Object?>['wat', 1],
        <Object?>[1, 1],
      ];

      // Act
      Result<int> decode(ResultSerial serial) => Result<int>.fromSerial(
        serial,
        decodeOk: (Object? value) => value! as int,
      );

      // Assert
      for (final ResultSerial wire in malformed) {
        expect(() => decode(wire), throwsFormatException);
      }
      expect(
        () => decode(<Object?>['err', 'not-an-object']),
        throwsFormatException,
      );
      final List<Map<String, Object?>> malformedProblems =
          <Map<String, Object?>>[
            <String, Object?>{'type': '', 'title': 'x', 'status': 500},
            <String, Object?>{'type': 'x', 'title': 1, 'status': 500},
            <String, Object?>{'type': 'x', 'title': 'x', 'status': '500'},
            <String, Object?>{
              'type': 'x',
              'title': 'x',
              'status': 500,
              'detail': 1,
            },
            <String, Object?>{
              'type': 'x',
              'title': 'x',
              'status': 500,
              'instance': 1,
            },
            <String, Object?>{
              'type': 'x',
              'title': 'x',
              'status': 500,
              'recoverable': 'true',
            },
            <String, Object?>{
              'type': 'x',
              'title': 'x',
              'status': 500,
              'data': <Object?>[],
            },
          ];
      for (final Map<String, Object?> wire in malformedProblems) {
        expect(() => decode(<Object?>['err', wire]), throwsFormatException);
      }
    });
  });

  group('FutureResult', () {
    test(
      'composes sync and async callbacks while preserving failures',
      () async {
        // Arrange
        final Future<Result<int>> ok = Future<Result<int>>.value(
          const Result<int>.ok(21),
        );
        final Future<Result<int>> err = Future<Result<int>>.value(
          Result<int>.err(problem),
        );

        // Act
        final Result<int> mapped = await ok.map((int value) async => value * 2);
        final Result<int> skippedMap = await err.map(
          (int value) async => value * 2,
        );
        final Result<String> chained = await ok.andThen(
          (int value) async => Result<String>.ok('$value!'),
        );
        final Result<int> skippedMapErr = await ok.mapErr(
          (Problem value) async => Problem(
            type: value.type,
            title: 'Unreachable',
            status: value.status,
          ),
        );
        final Result<int> mappedErr = await err.mapErr(
          (Problem value) async => Problem(
            type: value.type,
            title: 'Async mapped',
            status: value.status,
          ),
        );
        final Result<String> skippedChain = await err.andThen(
          (int value) => Result<String>.ok('$value!'),
        );
        final String okMatch = await ok.match(
          ok: (int value) async => 'ok:$value',
          err: (Problem value) => 'err:${value.status}',
        );
        final String errMatch = await err.match(
          ok: (int value) => 'ok:$value',
          err: (Problem value) async => 'err:${value.status}',
        );

        // Assert
        expect(mapped.unwrap(), 42);
        expect(skippedMap.unwrapErr(), same(problem));
        expect(chained.unwrap(), '21!');
        expect(skippedMapErr.unwrap(), 21);
        expect(mappedErr.unwrapErr().title, 'Async mapped');
        expect(skippedChain.unwrapErr(), same(problem));
        expect(okMatch, 'ok:21');
        expect(errMatch, 'err:422');
        expect(await ok.unwrap(), 21);
        expect(await err.unwrapErr(), same(problem));
      },
    );

    test('async callback failures remain thrown errors', () async {
      // Arrange
      final Future<Result<int>> ok = Future<Result<int>>.value(
        const Result<int>.ok(21),
      );

      // Act
      final Future<Result<int>> poisoned = ok.map<int>(
        (int _) => Future<int>.error(StateError('poison')),
      );

      // Assert
      await expectLater(poisoned, throwsStateError);
    });
  });
}
