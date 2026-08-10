import 'package:diene_problems/diene_problems.dart' show Problem;
import 'package:diene_result/diene_result.dart';

/// Plain-throw assertion helpers (dependency-light: `AssertionError` is
/// `dart:core`, no `test`/`matcher` import). Consumers get the same
/// unwrap-or-fail ergonomics in every test without per-test boilerplate.

/// Assert [result] is [Ok] and return its value; throws otherwise.
T expectOk<T>(Result<T> result, {String? because}) => switch (result) {
  Ok<T>(:final value) => value,
  Err<T>(:final problem) => throw AssertionError(
    'expected Ok but got Err(${problem.type}, ${problem.status})'
    '${because == null ? '' : ' — $because'}',
  ),
};

/// Assert [result] is [Err] and return its problem; throws otherwise.
Problem expectErr<T>(Result<T> result, {String? because}) => switch (result) {
  Ok<T>(:final value) => throw AssertionError(
    'expected Err but got Ok($value)${because == null ? '' : ' — $because'}',
  ),
  Err<T>(:final problem) => problem,
};

/// Assert [result] is an [Err] whose problem has [type]; returns the problem.
Problem expectProblemType<T>(Result<T> result, String type) {
  final Problem problem = expectErr(result);
  if (problem.type != type) {
    throw AssertionError(
      'expected problem type "$type" but got "${problem.type}"',
    );
  }
  return problem;
}

/// Assert a condition, throwing [AssertionError] with [message] on failure.
void check(bool condition, String message) {
  if (!condition) {
    throw AssertionError(message);
  }
}
