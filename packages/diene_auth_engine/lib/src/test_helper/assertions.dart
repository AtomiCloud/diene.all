import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import '../onboarding/onboarding_phase.dart';

/// Raised by the plain-throw assertion helpers on a failed expectation. Kept
/// framework-free so the TestHelper stays dependency-light (no `matcher`).
final class AuthAssertionError extends Error {
  AuthAssertionError(this.message);

  final String message;

  @override
  String toString() => 'AuthAssertionError: $message';
}

/// Plain-throw assertion helpers for auth-engine [Result]/[Option]/phase tests.
abstract final class AuthExpect {
  /// Asserts [result] is a [Ok] and returns its value.
  static T ok<T>(Result<T> result, {String? reason}) => result.match(
    ok: (T value) => value,
    err: (Problem problem) =>
        throw AuthAssertionError(reason ?? 'expected Ok but got Err($problem)'),
  );

  /// Asserts [result] is a [Err] and returns its problem.
  static Problem err<T>(Result<T> result, {String? reason}) => result.match(
    ok: (T value) =>
        throw AuthAssertionError(reason ?? 'expected Err but got Ok($value)'),
    err: (Problem problem) => problem,
  );

  /// Asserts [result] is a [Err] whose problem `type` equals [type].
  static Problem errType<T>(Result<T> result, String type) {
    final Problem problem = err(result);
    if (problem.type != type) {
      throw AuthAssertionError(
        'expected Err type "$type" but got "${problem.type}"',
      );
    }
    return problem;
  }

  /// Asserts [option] is [Some] and returns its value.
  static T some<T>(Option<T> option, {String? reason}) => option.match(
    some: (T value) => value,
    none: () =>
        throw AuthAssertionError(reason ?? 'expected Some but got None'),
  );

  /// Asserts [option] is [None].
  static void none<T>(Option<T> option, {String? reason}) => option.match(
    some: (T value) => throw AuthAssertionError(
      reason ?? 'expected None but got Some($value)',
    ),
    none: () {},
  );

  /// Asserts the terminal onboarding [phase] equals [expected].
  static void phase(OnboardingPhase actual, OnboardingPhase expected) {
    if (actual != expected) {
      throw AuthAssertionError('expected phase $expected but got $actual');
    }
  }

  /// Asserts [problem] carries the expected `status`.
  static void status(Problem problem, int expected) {
    if (problem.status != expected) {
      throw AuthAssertionError(
        'expected status $expected but got ${problem.status}',
      );
    }
  }
}
