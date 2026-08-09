/// Dependency-light assertions for consumers of `package:diene_dart_lib`.
///
/// This library deliberately depends on no test framework. A mismatch throws
/// [NoteAssertionFailure] (a [StateError]), so it works with `package:test`,
/// any other runner, or plain `dart run`.
library;

import 'diene_dart_lib.dart';

/// Thrown when a dependency-light [Note] assertion fails.
///
/// Extends [StateError] so consumers can catch it as a `StateError` or by its
/// concrete type.
final class NoteAssertionFailure extends StateError {
  /// Creates an assertion failure with a consumer-facing diagnostic.
  NoteAssertionFailure(super.message);
}

/// Asserts that [summarizeNote] renders [note] to [expected] at [maxLength].
///
/// Throws [NoteAssertionFailure] on mismatch and propagates the [ArgumentError]
/// from [summarizeNote] when [maxLength] is not positive.
void assertNoteSummary(
  Note note,
  String expected, {
  int maxLength = defaultSummaryLength,
}) {
  final String actual = summarizeNote(note, maxLength: maxLength);
  if (actual != expected) {
    throw NoteAssertionFailure(
      'Expected summary "$expected" but found "$actual".',
    );
  }
}
