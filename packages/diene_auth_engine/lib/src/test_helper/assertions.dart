import '../contracts/problem.dart';
import '../contracts/result.dart';
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
  /// Asserts [result] is a [Success] and returns its value.
  static T ok<T>(Result<T> result, {String? reason}) => result.match(
    onSuccess: (T value) => value,
    onFailure: (Problem problem) => throw AuthAssertionError(
      reason ?? 'expected Success but got Failure($problem)',
    ),
  );

  /// Asserts [result] is a [Failure] and returns its problem.
  static Problem err<T>(Result<T> result, {String? reason}) => result.match(
    onSuccess: (T value) => throw AuthAssertionError(
      reason ?? 'expected Failure but got Success($value)',
    ),
    onFailure: (Problem problem) => problem,
  );

  /// Asserts [result] is a [Failure] whose problem `type` equals [type].
  static Problem errType<T>(Result<T> result, String type) {
    final Problem problem = err(result);
    if (problem.type != type) {
      throw AuthAssertionError(
        'expected Failure type "$type" but got "${problem.type}"',
      );
    }
    return problem;
  }

  /// Asserts [option] is [Some] and returns its value.
  static T some<T>(Option<T> option, {String? reason}) => option.match(
    onSome: (T value) => value,
    onNone: () =>
        throw AuthAssertionError(reason ?? 'expected Some but got None'),
  );

  /// Asserts [option] is [None].
  static void none<T>(Option<T> option, {String? reason}) => option.match(
    onSome: (T value) => throw AuthAssertionError(
      reason ?? 'expected None but got Some($value)',
    ),
    onNone: () {},
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
