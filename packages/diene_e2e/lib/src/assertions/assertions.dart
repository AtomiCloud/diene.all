/// Plain-throw assertion helpers for consumer journey/e2e tests.
///
/// Dependency-light by rule: these throw [JourneyAssertionError] on failure
/// rather than depending on `package:test` or `package:matcher`, so importing
/// `package:diene_e2e/test_helper.dart` never drags a test framework into a
/// consumer's dependency graph. Consumers use them inside whatever test runner
/// they already have.
library;

import '../journey/journey.dart';

/// Thrown by an assertion helper when a check fails.
class JourneyAssertionError extends Error {
  JourneyAssertionError(this.message);

  final String message;

  @override
  String toString() => 'JourneyAssertionError: $message';
}

/// Asserts the whole [result] succeeded, reporting the first failing step.
void expectJourneyOk(JourneyResult result) {
  if (result.ok) return;
  final JourneyStepResult? failure = result.firstFailure;
  final String where = failure == null
      ? 'unknown step'
      : "step '${failure.name}'${failure.detail == null ? '' : ' — ${failure.detail}'}";
  throw JourneyAssertionError('expected journey to pass, but failed at $where');
}

/// Asserts the journey failed at the step named [stepName] (a negative-path
/// assertion — e.g. a replayed nonce must abort the handoff step).
void expectJourneyFailedAt(JourneyResult result, String stepName) {
  final JourneyStepResult? failure = result.firstFailure;
  if (failure == null) {
    throw JourneyAssertionError(
      "expected journey to fail at '$stepName', but it passed",
    );
  }
  if (failure.name != stepName) {
    throw JourneyAssertionError(
      "expected journey to fail at '$stepName', but it failed at '${failure.name}'",
    );
  }
}

/// Asserts [actual] equals [expected], with an optional [reason] for context.
void expectEquals<T>(T actual, T expected, {String? reason}) {
  if (actual == expected) return;
  final String suffix = reason == null ? '' : ' ($reason)';
  throw JourneyAssertionError('expected <$expected> but got <$actual>$suffix');
}

/// Asserts [condition] holds, throwing with [message] otherwise.
void expectTrue(bool condition, String message) {
  if (!condition) throw JourneyAssertionError(message);
}
