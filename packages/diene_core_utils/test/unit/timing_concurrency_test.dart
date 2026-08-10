import 'dart:async';

import 'package:diene_core_utils/diene_core_utils.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

void main() {
  group('sleep', () {
    test('zero waits successfully', () async {
      final Result<void> slept = await sleep(Duration.zero);
      expect(slept.isOk, isTrue);
    });

    test('a positive duration actually elapses', () async {
      final Stopwatch clock = Stopwatch()..start();
      final Result<void> slept = await sleep(const Duration(milliseconds: 20));
      clock.stop();
      expect(slept.isOk, isTrue);
      expect(clock.elapsedMilliseconds, greaterThanOrEqualTo(15));
    });

    test('a negative duration fails as a value and schedules no timer', () async {
      final Stopwatch clock = Stopwatch()..start();
      final Result<void> slept = await sleep(const Duration(seconds: -30));
      clock.stop();

      expect(slept.isErr, isTrue);
      // The whole point: it returns immediately rather than throwing or waiting.
      expect(clock.elapsedMilliseconds, lessThan(1000));
      final Problem problem = slept.unwrapErr();
      expect(problem.status, 400);
      expect(problem.data['util'], 'timing');
      expect(problem.data['code'], 'invalid_input');
      expect(problem.data['field'], 'duration');
      expect(problem.type, endsWith('timing_invalid_input'));
    });
  });

  group('mapWithConcurrency', () {
    test('preserves input order regardless of completion order', () async {
      // Later items finish FIRST, so an implementation that appended on
      // completion would produce [3, 2, 1].
      final Result<List<int>> mapped = await mapWithConcurrency<int, int>(
        <int>[1, 2, 3],
        3,
        (int value) async {
          await Future<void>.delayed(Duration(milliseconds: 30 - value * 10));
          return Ok<int>(value);
        },
      );
      expect(mapped.unwrap(), <int>[1, 2, 3]);
    });

    test('never exceeds the concurrency bound', () async {
      int inFlight = 0;
      int peak = 0;
      final Result<List<int>> mapped = await mapWithConcurrency<int, int>(
        List<int>.generate(20, (int i) => i),
        3,
        (int value) async {
          inFlight += 1;
          peak = inFlight > peak ? inFlight : peak;
          await Future<void>.delayed(const Duration(milliseconds: 2));
          inFlight -= 1;
          return Ok<int>(value * 2);
        },
      );
      expect(mapped.unwrap(), List<int>.generate(20, (int i) => i * 2));
      expect(peak, lessThanOrEqualTo(3));
      expect(
        peak,
        greaterThan(1),
        reason: 'work did not actually run in parallel',
      );
    });

    test(
      'a bound larger than the item count is clamped, not spun up idle',
      () async {
        int started = 0;
        final Result<List<int>> mapped = await mapWithConcurrency<int, int>(
          <int>[1, 2],
          50,
          (int value) async {
            started += 1;
            return Ok<int>(value);
          },
        );
        expect(mapped.unwrap(), <int>[1, 2]);
        expect(started, 2);
      },
    );

    test(
      'an empty input yields an empty list without calling the mapper',
      () async {
        int called = 0;
        final Result<List<int>> mapped = await mapWithConcurrency<int, int>(
          <int>[],
          4,
          (int value) async {
            called += 1;
            return Ok<int>(value);
          },
        );
        expect(mapped.unwrap(), isEmpty);
        expect(called, 0);
      },
    );

    test('the result list is unmodifiable', () async {
      final Result<List<int>> mapped = await mapWithConcurrency<int, int>(
        <int>[1],
        1,
        (int value) async => Ok<int>(value),
      );
      expect(() => mapped.unwrap().add(2), throwsUnsupportedError);
    });

    test('a bound below one fails as a value and runs no mapper', () async {
      for (final int bound in <int>[0, -1]) {
        int called = 0;
        final Result<List<int>> mapped = await mapWithConcurrency<int, int>(
          <int>[1, 2],
          bound,
          (int value) async {
            called += 1;
            return Ok<int>(value);
          },
        );
        expect(mapped.isErr, isTrue, reason: 'bound $bound was accepted');
        expect(called, 0);
        final Problem problem = mapped.unwrapErr();
        expect(problem.data['util'], 'concurrency');
        expect(problem.data['field'], 'concurrency');
        expect(problem.status, 400);
      }
    });

    test(
      'the first failure short-circuits and stops claiming new work',
      () async {
        final List<int> attempted = <int>[];
        final Result<List<int>> mapped = await mapWithConcurrency<int, int>(
          List<int>.generate(20, (int i) => i),
          2,
          (int value) async {
            attempted.add(value);
            await Future<void>.delayed(const Duration(milliseconds: 1));
            if (value == 1) {
              return Err<int>(_failure('item 1 refused'));
            }
            return Ok<int>(value);
          },
        );

        expect(mapped.isErr, isTrue);
        expect(mapped.unwrapErr().title, 'item 1 refused');
        expect(
          attempted.length,
          lessThan(20),
          reason: 'work kept being claimed after the failure',
        );
      },
    );

    test('the LOWEST failing index wins, not the first to complete', () async {
      // Index 3 fails immediately; index 1 fails later. The outcome must be
      // index 1's problem, so the result does not depend on timing.
      final Result<List<int>> mapped = await mapWithConcurrency<int, int>(
        <int>[0, 1, 2, 3],
        4,
        (int value) async {
          if (value == 3) {
            return Err<int>(_failure('index 3'));
          }
          if (value == 1) {
            await Future<void>.delayed(const Duration(milliseconds: 30));
            return Err<int>(_failure('index 1'));
          }
          return Ok<int>(value);
        },
      );
      expect(mapped.unwrapErr().title, 'index 1');
    });

    test('a single failing item reports its problem unchanged', () async {
      final Problem original = _failure('only item');
      final Result<List<int>> mapped = await mapWithConcurrency<int, int>(
        <int>[1],
        1,
        (int value) async => Err<int>(original),
      );
      expect(mapped.unwrapErr(), same(original));
    });
  });

  group('fuzzyIncludes', () {
    test('matches case-insensitively anywhere in the haystack', () {
      expect(fuzzyIncludes('Hello World', 'hello'), isTrue);
      expect(fuzzyIncludes('Hello World', 'WORLD'), isTrue);
      expect(fuzzyIncludes('Hello World', 'lo Wo'), isTrue);
    });

    test('an empty needle is always contained', () {
      expect(fuzzyIncludes('anything', ''), isTrue);
      expect(fuzzyIncludes('', ''), isTrue);
    });

    test('a missing needle is not contained', () {
      expect(fuzzyIncludes('Hello', 'xyz'), isFalse);
      expect(fuzzyIncludes('', 'x'), isFalse);
    });
  });
}

Problem _failure(String message) => utilProblem(
  util: UtilName.concurrency,
  code: UtilErrorCode.delegated,
  operation: 'test',
  message: message,
);
