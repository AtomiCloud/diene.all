/// Bounded-concurrency mapping over a fallible mapper.
library;

import 'dart:async';

import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';

import 'util_problem.dart';

/// Maps [items] through [mapper] with at most [concurrency] calls in flight.
///
/// Results preserve INPUT order regardless of completion order. Work is pulled,
/// not pushed: a fixed pool of [concurrency] workers each claims the next
/// unclaimed index only when it becomes free, so no mapper is invoked eagerly
/// beyond the bound. Dart has no core equivalent — `Future.wait` is unbounded —
/// which is why this member ships rather than deferring to the SDK.
///
/// A [concurrency] below 1 is reported as an `invalid_input` [Problem] and no
/// mapper runs. The first failure stops new work from being claimed, and the
/// [Problem] of the LOWEST failing input index is returned unchanged so the
/// outcome does not depend on completion order. Calls already in flight are
/// awaited, so this never leaves a dangling future behind.
Future<Result<List<R>>> mapWithConcurrency<T, R>(
  Iterable<T> items,
  int concurrency,
  Future<Result<R>> Function(T item) mapper,
) async {
  if (concurrency < 1) {
    return invalidUtilInput<List<R>>(
      util: UtilName.concurrency,
      operation: 'mapWithConcurrency',
      field: 'concurrency',
      message: 'concurrency must be at least 1',
    );
  }

  final List<T> pending = items.toList(growable: false);
  if (pending.isEmpty) {
    return Ok<List<R>>(List<R>.unmodifiable(<R>[]));
  }

  final List<R?> slots = List<R?>.filled(pending.length, null);
  final int workers = concurrency < pending.length
      ? concurrency
      : pending.length;
  int next = 0;
  int? failedIndex;
  Problem? failure;
  bool stopped = false;

  Future<void> work() async {
    while (!stopped && next < pending.length) {
      final int index = next;
      next += 1;
      final Result<R> outcome = await mapper(pending[index]);
      switch (outcome) {
        case Ok<R>(value: final R value):
          slots[index] = value;
        case Err<R>(problem: final Problem problem):
          if (failedIndex == null || index < failedIndex!) {
            failedIndex = index;
            failure = problem;
          }
          stopped = true;
      }
    }
  }

  await Future.wait<void>(<Future<void>>[
    for (int worker = 0; worker < workers; worker += 1) work(),
  ]);

  final Problem? observed = failure;
  if (observed != null) {
    return Err<List<R>>(observed);
  }
  return Ok<List<R>>(List<R>.unmodifiable(slots.cast<R>()));
}
